# Mainline Linux kernel fork for the Xiaomi Pad 6S Pro ("sheng", SM8550P),
# tracking https://github.com/ianchb/sm8550-mainline.
#
# IMPORTANT: the config comes from https://github.com/ianchb/debian-sheng's
# own repo-root `sm8550.config` (9,372 lines, a genuinely complete,
# hand-maintained .config -- confirmed EXT4_FS=y, checked against the
# actual file backing the reference project's confirmed-working boot),
# NOT `sm8550-mainline`'s in-tree arch/arm64/configs/sm8550.config, which
# despite the identical filename is a completely different, much smaller
# (~80-line) kbuild config *fragment* meant to be merged onto arm64's
# generic defconfig. Using the in-tree fragment directly with `cp + make
# olddefconfig` (rather than merging it onto defconfig first) silently
# produces a kernel with no EXT4_FS support at all and was the root cause
# of an unbootable image -- these two "sm8550.config" files are not
# interchangeable despite the name coincidence. Recipe matches the
# reference project's own build.sh exactly: `cp sm8550.config .config &&
# make olddefconfig`, then our own additions merged on top.
{ lib
, stdenv
, fetchFromGitHub
, fetchurl
, linuxManualConfig
, buildPackages
, flex
, bison
, bc
, perl
, python3
, elfutils
, openssl
, ncurses
  # linuxPackagesFor and other NixOS kernel plumbing call
  # kernel.override { kernelPatches = ...; features = ...; etc. } -- catch
  # and forward whatever extra args show up instead of declaring each one.
, ...
}@args:

let
  # Pinned to the tip of `sheng-7.2.0` as of 2026-08-18. That branch is a
  # rolling dev target, so re-pin periodically:
  #   curl -s https://api.github.com/repos/ianchb/sm8550-mainline/commits/sheng-7.2.0 | jq -r .sha
  rawSrc = fetchFromGitHub {
    owner = "ianchb";
    repo = "sm8550-mainline";
    rev = "005aa8ccae670a8e731a279e2a802ac75e1e662d";
    hash = "sha256-IGPK6s0gtPZ587NnLotFvDXx9IFWbo52PHjTNXQTQns=";
  };

  # TEMPORARY telemetry (SPEC.md task #5 log): U-Boot's own DSI command
  # DMA hangs on command #0 (CMD_MODE_DMA_BUSY never clears) despite
  # every register, clock, power rail, reset line, and interrupt mask
  # matching this exact working Linux boot bit-for-bit. dynamic_debug
  # is a dead end for this driver -- DBG() in dsi.h resolves to
  # DRM_DEBUG_DRIVER (a drm.debug bitmask category, not a per-callsite
  # dyndbg control node), so there are zero dsi_host.c/dsi_manager.c
  # entries in /sys/kernel/debug/dynamic_debug/control to enable.
  # Unconditional pr_info() calls sidestep that entirely. Instruments:
  # msm_dsi_host_power_on() entry, dsi_ctrl_enable()'s final DSI_CTRL
  # write, dsi_cmd_dma_tx()'s trigger+completion-wait (the actual
  # per-command send/wait this session's U-Boot driver was modeled
  # after), and dsi_host_irq()'s raw isr value on every single IRQ --
  # a ground-truth trace of what a WORKING command transfer's
  # completion signal actually looks like, to diff against U-Boot's.
  # linuxManualConfig's builder doesn't accept a bare postPatch
  # argument (confirmed: "function 'anonymous lambda' called with
  # unexpected argument 'postPatch'") -- pre-patch the source into its
  # own derivation instead and feed that in as `src`.
  src = stdenv.mkDerivation {
    pname = "sheng-kernel-src-traced";
    inherit version;
    src = rawSrc;
    dontConfigure = true;
    dontBuild = true;
    nativeBuildInputs = [ perl ];
    postPatch = ''
      perl -0777 -pi -e '
        s/(#include <linux\/interrupt\.h>\n)/$1#include <linux\/ktime.h>\n/;

        s/(\tstruct msm_dsi_host \*msm_host = to_msm_dsi_host\(host\);\n\tconst struct msm_dsi_cfg_handler \*cfg_hnd = msm_host->cfg_hnd;\n\tint ret = 0;\n\n\tmutex_lock\(&msm_host->dev_mutex\);)/$1\n\tpr_info("SHENG_TRACE: power_on enter id=%d ktime=%lld\\n", msm_host->id, ktime_get_ns());/;

        s/(\tdata \|= DSI_CTRL_ENABLE;\n\n\tdsi_write\(msm_host, REG_DSI_CTRL, data\);\n)/$1\tpr_info("SHENG_TRACE: ctrl_enable id=%d ctrl=0x%x ktime=%lld\\n", msm_host->id, data, ktime_get_ns());\n/;

        s/(\treinit_completion\(&msm_host->dma_comp\);\n\n\tdsi_wait4video_eng_busy\(msm_host\);\n\n)(\ttriggered = msm_dsi_manager_cmd_xfer_trigger\(\n\t\t\t\t\t\tmsm_host->id, dma_base, len\);\n)/$1\tpr_info("SHENG_TRACE: dma_tx enter id=%d dma_base=0x%llx len=%d ktime=%lld\\n", msm_host->id, dma_base, len, ktime_get_ns());\n$2/;

        s/(\t\telse\n\t\t\tret = len;\n\t} else \{\n\t\tret = len;\n\t\}\n)(\n\treturn ret;\n\})/$1\tpr_info("SHENG_TRACE: dma_tx exit id=%d triggered=%d ret=%d ktime=%lld\\n", msm_host->id, triggered, ret, ktime_get_ns());$2/;

        s/(\tDBG\("isr=0x%x, id=%d", isr, msm_host->id\);\n)/$1\tpr_info("SHENG_TRACE: irq id=%d isr=0x%x ktime=%lld\\n", msm_host->id, isr, ktime_get_ns());\n/;
      ' drivers/gpu/drm/msm/dsi/dsi_host.c

      test "$(grep -c SHENG_TRACE drivers/gpu/drm/msm/dsi/dsi_host.c)" = "5"

      # PPS CAPTURE (SPEC.md task #5 log). U-Boot's driver now matches
      # this kernel bit-for-bit across every register that can be
      # compared: DSI0 39/39, DSI1 39/39, DPU pipeline 55/55, PHY 31/31,
      # and the DSC encoder reports the same running status. A colour
      # generated INSIDE the DPU pipe (SSPP solid fill, no memory fetch)
      # still does not appear on the panel.
      #
      # That leaves exactly one artifact no register audit can cover,
      # because it is not a register: the 128-byte DSC PPS transmitted
      # to the panel. U-Boot sends a hand-transcribed blob; this kernel
      # generates its own with drm_dsc_pps_payload_pack(). The panel's
      # entire DSC decoder configuration comes from those 128 bytes, and
      # a decoder configured differently from the encoder feeding it
      # emits nothing usable while reporting no error anywhere.
      #
      # Dump the exact bytes this kernel sends, right after packing and
      # before transmission, so they can be diffed against U-Boot's blob.
      perl -0777 -pi -e '
        s/(\tdrm_dsc_pps_payload_pack\(&pps, &pinfo->desc->dsc\);\n)/$1\tprint_hex_dump(KERN_INFO, "SHENG_PPS: ", DUMP_PREFIX_OFFSET, 16, 1, &pps, sizeof(pps), false);\n/;
      ' drivers/gpu/drm/panel/panel-novatek-nt36532e.c

      test "$(grep -c SHENG_PPS drivers/gpu/drm/panel/panel-novatek-nt36532e.c)" = "1"

      # SEQUENCE TRACE (SPEC.md task #5 log). Every value that can be
      # compared between U-Boot and this kernel is now identical --
      # MDSS wrapper, both DSI hosts (39 regs each), the PHY's CMN and
      # per-lane banks, the whole DPU pipeline, all 128 PPS bytes, the
      # 87-command init sequence, the KTZ8866, and the panel GPIOs
      # measured electrically. The panel still shows nothing and does
      # not answer a DCS read.
      #
      # Identical state means the remaining difference cannot BE state:
      # it has to be the order and spacing of operations, which a
      # final-state comparison structurally cannot see. Timestamp the
      # ordering points so U-Boot can replicate the real timeline
      # instead of one inferred from reading the source.
      perl -0777 -pi -e '
        s/(#include <drm\/display\/drm_dsc_helper\.h>\n)/$1#include <linux\/ktime.h>\n/;
        s/(static void nt36532e_reset\(struct panel_info \*pinfo\)\n\{\n)/$1\tpr_info("SHENG_SEQ: panel_reset enter ktime=%lld\\n", ktime_get_ns());\n/;
        s/(\tret = regulator_bulk_enable\(ARRAY_SIZE\(pinfo->supplies\), pinfo->supplies\);\n)/\tpr_info("SHENG_SEQ: panel_prepare enter ktime=%lld\\n", ktime_get_ns());\n$1/;
        s/(\tret = pinfo->desc->init_sequence\(pinfo\);\n)/\tpr_info("SHENG_SEQ: init_seq enter ktime=%lld\\n", ktime_get_ns());\n$1\tpr_info("SHENG_SEQ: init_seq exit ret=%d ktime=%lld\\n", ret, ktime_get_ns());\n/;
      ' drivers/gpu/drm/panel/panel-novatek-nt36532e.c

      perl -0777 -pi -e '
        s/(#include "dsi\.h"\n)/$1#include <linux\/ktime.h>\n/;
        s/(\tret = dsi_mgr_bridge_power_on\(bridge\);\n)/\tpr_info("SHENG_SEQ: bridge_pre_enable id=%d ktime=%lld\\n", id, ktime_get_ns());\n$1/;
        s/(\tret = msm_dsi_host_enable\(host\);\n)/\tpr_info("SHENG_SEQ: host_enable_video id=%d ktime=%lld\\n", id, ktime_get_ns());\n$1/;
      ' drivers/gpu/drm/msm/dsi/dsi_manager.c

      test "$(grep -c SHENG_SEQ drivers/gpu/drm/panel/panel-novatek-nt36532e.c)" = "4"
      test "$(grep -c SHENG_SEQ drivers/gpu/drm/msm/dsi/dsi_manager.c)" = "2"

      # INTF TIMING ENGINE TRACE (SPEC.md task #5 log). The measured
      # kernel timeline already shows host_enable_video at 743.050ms and
      # init_seq exit at 952.569ms -- 200ms of DCS traffic on a link
      # already in video mode. Replicating that in U-Boot wedged the
      # command DMA at command #26.
      #
      # The open question is whether the DPU is feeding actual pixels
      # during that window. dpu_hw_intf_enable_timing_engine() is the
      # exact write that opens the pixel firehose (INTF_TIMING_ENGINE_EN),
      # so timestamping it settles it:
      #
      #   fires AFTER init_seq exit  -> commands travel through ~100%
      #     blanking, and our failure means our video engine misbehaves
      #     with no data behind it.
      #   fires BEFORE host_enable_video -> Linux sends its whole init
      #     sequence WITH pixels already streaming, i.e. the opposite of
      #     the blanking-squeeze model, and our no-pixel window was
      #     never the same condition at all.
      perl -0777 -pi -e '
        s/(#include "dpu_hw_intf\.h"\n)/$1#include <linux\/ktime.h>\n/;
        s/(\tstruct dpu_hw_blk_reg_map \*c = &intf->hw;\n\t\/\* Note: Display interface select is handled in top block hw layer \*\/\n)/$1\tpr_info("SHENG_SEQ: intf_timing_engine idx=%d enable=%d ktime=%lld\\n", intf->idx, enable, ktime_get_ns());\n/;
      ' drivers/gpu/drm/msm/disp/dpu1/dpu_hw_intf.c

      test "$(grep -c SHENG_SEQ drivers/gpu/drm/msm/disp/dpu1/dpu_hw_intf.c)" = "1"

      # DSI HOST WRITE TRACE (SPEC.md task #5 log).
      #
      # Every FINAL-STATE comparison now passes. U-Boot's driver matches
      # this kernel across DISPCC 4/4, DSI PHY 53/53 on both PHYs (CMN +
      # PLL, both locked, PHY_STATUS 0x1F), DSI0 39/39, DSI1 39/39, DPU
      # 50/50, the MDSS wrapper 3/3 and all 128 PPS bytes. The panel is
      # confirmed powered (bias enable set, FLAG=0, GPIO pads read back
      # high), the lanes are confirmed driven (LANE_STATUS 0x00001F00,
      # STOPSTATE clear, no contention, no PHY errors), and the panel
      # still answers nothing -- a DCS read with a genuine BTA returns
      # zero bytes even in a minimal command-mode-only configuration on a
      # freshly reset panel, before any init command.
      #
      # Identical end state means the difference cannot BE end state.
      # Notably, EVERY bug actually found in this driver was invisible to
      # state comparison: GCC_DISP_HF_AXI_CLK enabled too late, CTL_START
      # written in video mode, the INTF timing engine enabled before the
      # flush instead of after, the slave PHY PLL never configured, and
      # DSI1's byte/pixel clocks parented to the wrong PLL. Those are
      # ordering and transient faults.
      #
      # So capture the SEQUENCE, not the state: log every write the DSI
      # host makes, in order, with its value. dsi_write() is the single
      # choke point for the whole host register space, and its `reg` is
      # already the LOGICAL offset -- msm_host->ctrl_base has the DSI 6G
      # +4 shift baked in -- so these offsets line up directly with the
      # ones sheng_mdss_hw.zig uses, no translation needed.
      #
      # This catches the one class our audits structurally cannot see: a
      # register written transiently and later overwritten, which never
      # survives to be read back.
      #
      # Counter-capped so a boot cannot flood the ring buffer: bring-up
      # is roughly 60 writes per host plus ~5 per DCS command across 87
      # commands on two hosts, so a few thousand lines covers it with
      # room to spare.
      perl -0777 -pi -e '
        s/(static inline void dsi_write\(struct msm_dsi_host \*msm_host, u32 reg, u32 data\)\n\{\n)(\twritel\(data, msm_host->ctrl_base \+ reg\);\n)/$1\t{\n\t\tstatic int sheng_w_n;\n\t\tif (sheng_w_n < 4000) {\n\t\t\tsheng_w_n++;\n\t\t\tpr_info("SHENG_W id=%d off=0x%03x val=0x%08x\\n", msm_host->id, reg, data);\n\t\t}\n\t}\n$2/;
      ' drivers/gpu/drm/msm/dsi/dsi_host.c

      test "$(grep -c SHENG_W drivers/gpu/drm/msm/dsi/dsi_host.c)" = "1"

      # FULL DCS STREAM DUMP (SPEC.md task #5 log).
      #
      # The init is now known not to take, while the command TABLE is
      # byte-identical to this kernel's (87/87, diffed mechanically) and
      # command #0's packet is verified correct in DRAM. What has never
      # been compared is the actual transmitted stream: all ~95 transfers
      # in order with their full payloads -- in particular the 132-byte PPS
      # packet, which U-Boot builds through a separate raw-long-write path
      # that has never been byte-checked against anything.
      #
      # dsi_cmd_dma_add() is the single point where every outgoing packet
      # is assembled into the DMA buffer in MSM format, so dumping `data`
      # here captures exactly what the hardware will fetch, header and
      # payload together, for every command.
      #
      # Capped and truncated per packet: 20 bytes is enough to identify any
      # command and to check the PPS header plus its first 16 payload bytes.
      perl -0777 -pi -e '
        s/(\tif \(cfg_hnd->ops->tx_buf_put\)\n)/\t{\n\t\tstatic int sheng_c_n;\n\t\tif (sheng_c_n < 200) {\n\t\t\tsheng_c_n++;\n\t\t\tprint_hex_dump(KERN_INFO, "SHENG_C: ", DUMP_PREFIX_NONE, 32, 1, data, len < 20 ? len : 20, false);\n\t\t}\n\t}\n$1/;
      ' drivers/gpu/drm/msm/dsi/dsi_host.c

      test "$(grep -c SHENG_C drivers/gpu/drm/msm/dsi/dsi_host.c)" = "1"

      # DSI PHY WRITE TRACE (SPEC.md task #5 log).
      #
      # The host trace above already paid for itself: diffing the 23
      # offsets Linux writes on DSI0 against ours found VID_CFG1, which
      # dsi.xml puts at 0x01c while this driver had it at 0x010 -- so we
      # were writing an undocumented register and never writing the real
      # one. Invisible to every audit, because a self-selected offset list
      # cannot contain a register nobody thought to look at.
      #
      # The PHY has exactly the same exposure and is now the prime suspect:
      # the panel never answers a BTA, the host side is proven correct, and
      # our PHY "53/53 match" only covers 53 offsets WE picked.
      #
      # dsi_phy_7nm.c has no dsi_write()-style choke point -- it calls
      # writel() directly -- so hook writel itself, scoped to this one
      # file. The helper is defined BEFORE the macro so its own call site
      # resolves to the real writel; every subsequent call in the file goes
      # through the wrapper. The file's includes are already processed by
      # then, so nothing outside it is affected.
      #
      # Offset encoding: ioremap preserves the page offset, and the PHY's
      # three sub-regions are mapped from 0x...000 (CMN), 0x...200 (lane)
      # and 0x...500 (PLL), so (addr & 0xfff) yields exactly the
      # phy_base-relative offset this driver already uses -- CMN 0x0xx,
      # lane 0x2xx, PLL 0x5xx-0x7xx. `pg` groups by mapping so DSI0 and
      # DSI1 can be told apart (DSI0 is enabled first).
      perl -0777 -pi -e '
        s/(#include "dsi_phy_7nm\.xml\.h"\n)/$1\nstatic inline void sheng_phy_wl(u32 val, void __iomem *addr)\n{\n\tstatic int sheng_p_n;\n\tif (sheng_p_n < 3000) {\n\t\tsheng_p_n++;\n\t\tpr_info("SHENG_P pg=%lx off=0x%03lx val=0x%08x\\n", (unsigned long)addr >> 12, (unsigned long)addr & 0xfff, val);\n\t}\n\twritel(val, addr);\n}\n#define writel(v, a) sheng_phy_wl((v), (a))\n/;
      ' drivers/gpu/drm/msm/dsi/phy/dsi_phy_7nm.c

      test "$(grep -c SHENG_P drivers/gpu/drm/msm/dsi/phy/dsi_phy_7nm.c)" = "1"

      # DPU WRITE TRACE (SPEC.md task #5 log).
      #
      # Last untraced block. The DSI host trace found VID_CFG1 at the wrong
      # offset; the PHY trace found PLL_PLL_OUTDIV_RATE missing and, more
      # importantly, that dsi_pll_7nm_vco_prepare() INTERLEAVES the two
      # PHYs (bias master, bias slave, start master PLL, dig-reset master,
      # dig-reset slave) where this driver finished the master entirely
      # before beginning the slave -- measured as slave CMN_PHY_STATUS 0x19
      # against live 0x1F.
      #
      # dpu_reg_write() is the single choke point behind DPU_REG_WRITE, and
      # the macro passes the register's own symbol name through as `name`
      # (#off), so the trace is self-labelling -- no offset table needed to
      # read it.
      #
      # blk is (blk_addr & 0xfffff): the DPU is one page-aligned ioremap, so
      # this yields the block's dpu_base-relative offset (CTL_0 0x15000,
      # SSPP 0x24000, LM_0 0x44000, INTF_1 0x35000, DCE 0x80000 ...), and
      # `off` is the register within it -- exactly how sheng_mdss_hw.zig
      # addresses them.
      perl -0777 -pi -e '
        s/(\twritel_relaxed\(val, c->blk_addr \+ reg_off\);\n)/\t{\n\t\tstatic int sheng_d_n;\n\t\tif (sheng_d_n < 4000) {\n\t\t\tsheng_d_n++;\n\t\t\tpr_info("SHENG_D blk=%05lx off=0x%03x val=0x%08x %s\\n", (unsigned long)c->blk_addr & 0xfffff, reg_off, val, name);\n\t\t}\n\t}\n$1/;
      ' drivers/gpu/drm/msm/disp/dpu1/dpu_hw_util.c

      test "$(grep -c SHENG_D drivers/gpu/drm/msm/disp/dpu1/dpu_hw_util.c)" = "1"

      # PANEL-INIT HANDOFF TEST, CORRECTED (SPEC.md task #5 log).
      #
      # The first version made nt36532e_prepare() return immediately, which
      # also skipped regulator_bulk_enable(). The panel driver still
      # REQUESTS those supplies in probe but never enabled them, so Linux's
      # unused-regulator cleanup would switch avdd/avee off and power down
      # the very panel U-Boot had just configured. Black was then
      # guaranteed regardless of whether U-Boot's init worked, so that
      # result cannot support the conclusion drawn from it.
      #
      # This version keeps regulator_bulk_enable() -- so the supplies stay
      # claimed and on -- and skips only nt36532e_reset() and the init
      # sequence. The DDIC therefore keeps exactly the configuration U-Boot
      # left it in, powered, while Linux drives its known-good video path.
      #
      #   renders -> U-Boot's panel init WORKS; fault is in our video path.
      #   black   -> U-Boot's panel init genuinely does not take.
      # IMPLEMENTED FOR REAL (was marker-only until now, so the test this
      # whole comment describes had never actually been run).
      #
      # Gated on a module parameter rather than compiled in unconditionally,
      # so the experiment can be flipped from U-Boot's bootargs
      # (panel_novatek_nt36532e.noinit=1) without a kernel rebuild each time
      # -- a U-Boot rebuild is ~1 minute, a kernel rebuild is not.
      perl -0777 -pi -e '
        s/(static void nt36532e_reset\(struct panel_info \*pinfo\)\n)/static bool sheng_noinit;\nmodule_param_named(noinit, sheng_noinit, bool, 0644);\nMODULE_PARM_DESC(noinit, "SHENG: skip the DCS init sequence only");\nstatic bool sheng_noreset;\nmodule_param_named(noreset, sheng_noreset, bool, 0644);\nMODULE_PARM_DESC(noreset, "SHENG: also skip the reset pulse (preserves a DDIC configured by U-Boot)");\n\n$1/;
        s/(\tnt36532e_reset\(pinfo\);\n)/\tif (sheng_noreset)\n\t\tpr_info("SHENG_NOINIT: skipping panel reset\\n");\n\telse\n$1/;
        s/(\tret = pinfo->desc->init_sequence\(pinfo\);\n)/\tif (sheng_noinit) {\n\t\tpr_info("SHENG_NOINIT: skipping init sequence\\n");\n\t\tret = 0;\n\t} else\n$1/;
        s/(\tint cur_vrefresh = drm_mode_vrefresh\(&pinfo->desc->modes\[cur_mode\]\);\n)/$1\n\tpr_info("SHENG_TAILONLY: marker only, full table sent\\n");\n/;
        s/devm_gpiod_get\(dev, "reset", GPIOD_OUT_HIGH\)/devm_gpiod_get(dev, "reset", sheng_noreset ? GPIOD_ASIS : GPIOD_OUT_HIGH)/;
        s/(\tpr_info\("SHENG_SEQ: init_seq exit[^\n]*\n)/$1\t{\n\t\tu8 shpm = 0xAA;\n\t\tint shr = mipi_dsi_dcs_get_power_mode(pinfo->dsi[0], &shpm);\n\n\t\tpr_info("SHENG_PM: after prepare noinit=%d noreset=%d ret=%d val=0x%02x\\n", sheng_noinit, sheng_noreset, shr, shpm);\n\t}\n/;
      ' drivers/gpu/drm/panel/panel-novatek-nt36532e.c

      test "$(grep -c SHENG_PM drivers/gpu/drm/panel/panel-novatek-nt36532e.c)" = "1"
      test "$(grep -c SHENG_NOINIT drivers/gpu/drm/panel/panel-novatek-nt36532e.c)" = "2"
      test "$(grep -c sheng_noinit drivers/gpu/drm/panel/panel-novatek-nt36532e.c)" = "4"
      test "$(grep -c sheng_noreset drivers/gpu/drm/panel/panel-novatek-nt36532e.c)" = "5"
      test "$(grep -c GPIOD_ASIS drivers/gpu/drm/panel/panel-novatek-nt36532e.c)" = "1"
      test "$(grep -c SHENG_TAILONLY drivers/gpu/drm/panel/panel-novatek-nt36532e.c)" = "1"

      # BREAK-LINUX PROBE: per-command PLL re-commit (SPEC.md task #5 log).
      #
      # We now have a SENSITIVE detector. Patching the kernel to send only
      # the 8-command DSC tail made the panel render glitchily rather than
      # not at all, so Linux's display responds to changes in the command
      # path. That lets us stop guessing what U-Boot is missing and instead
      # REMOVE things from Linux until it breaks.
      #
      # First candidate: msm_dsi_host_xfer_prepare() calls
      # link_clk_set_rate() before every command, which propagates to
      # dsi_pll_7nm_vco_set_rate() and re-commits the ENTIRE PLL
      # configuration -- ~30 PHY writes per command. U-Boot does this once
      # at bring-up. We added a replica (dsiPhyPllRecommit) and it changed
      # nothing, but we cannot replicate the clk-framework enable/disable
      # cycle that surrounds it.
      #
      #   Linux still renders -> the re-commit is irrelevant; drop it from
      #     consideration on both sides.
      #   Linux breaks        -> it is load-bearing, and the difference is
      #     in the part we could not replicate.
      # ANSWERED: skipping the per-command link_clk_set_rate() -- and with
      # it the ~30-write PLL re-commit before every DCS command -- left
      # Linux rendering normally. So that behaviour is irrelevant on both
      # sides. Combined with pm_runtime_get_sync and link_clk_enable being
      # pure refcounting on already-enabled resources, the per-command path
      # is now fully accounted for and is NOT where the difference lives.

      # BREAK-LINUX PROBE: is vddio required? (SPEC.md task #5 log)
      #
      # vreg_s3g_0p7 -- the panel's vddio -- reports num_users=1 under
      # Linux: the panel is its only consumer, so nothing else holds it up.
      # U-Boot votes it through a hand-rolled RPMh/RSC write whose only
      # confirmation is a local TCS acknowledgement, which this project's
      # notes say is not proof the vote reached the PMIC. It is the single
      # power rail in the whole display path we have never been able to
      # verify, and regulator_is_enabled() cannot help because the RPMh
      # driver caches state rather than reading hardware.
      #
      # So ask Linux instead: enable only avdd and avee, skip vddio.
      #   still renders -> vddio is already on (ABL leaves it, or it is
      #     effectively always-on) and the rail is exonerated.
      #   black/glitched -> vddio is genuinely required, and since only the
      #     panel votes for it, U-Boot's unverifiable RPMh vote becomes the
      #     prime suspect for why our DDIC never receives anything.
      # ANSWERED: Linux rendered completely normally with vddio never
      # enabled. The rail is already up regardless of who votes for it, so
      # U-Boot's unverifiable RPMh vote is exonerated and every panel supply
      # is now accounted for. Probe reverted; full regulator_bulk_enable
      # restored so the kernel stays a faithful oracle.

      # DCS READ ORACLE: does this panel answer a read AT ALL? (SPEC.md #5)
      #
      # U-Boot's one two-way liveness test -- a DCS Get Power Mode (0x0A)
      # with a real BTA -- returns sheng.rd1 = 0x01F7_0000: COUNT = 0 bytes,
      # RDBK empty. The 0x01F7 half confirms CMD_MODE_EN really was asserted
      # during the read, so unlike every earlier attempt (which silently ran
      # with the host still in video mode and never turned the bus around at
      # all) the BTA was genuinely issued. The panel simply did not answer.
      #
      # That has been read as "the DDIC never receives anything from us" --
      # but the inference only holds if a read is expected to work here in
      # the first place. On a bonded dual-DSI link driving a Novatek DDIC,
      # reads may simply not be supported, in which case an empty BTA says
      # nothing about our transmit path and has been misleading this
      # investigation for a long time.
      #
      # dsi_manager.c settles half of it: msm_dsi_manager_cmd_xfer() sets
      # need_sync = IS_SYNC_NEEDED() && !is_read, so reads deliberately go
      # out on DSI0 only -- exactly what U-Boot does. Same transaction, same
      # host, same panel. So run it from the kernel at the end of a KNOWN-
      # GOOD init, the precise mirror of where U-Boot issues its own.
      #
      #   ret > 0, plausible value -> reads work on this panel. U-Boot's
      #     empty BTA is then real evidence that our link is dead, and the
      #     hunt moves to the physical layer.
      #   ret < 0 / empty -> reads do not work here at all. The zero-byte
      #     BTA is an artefact, carries no information about the panel, and
      #     every conclusion resting on it has to be thrown out.
      perl -0777 -pi -e '
        s/(\tmipi_dsi_dcs_set_display_on_multi\(&dsi_ctx\);\n\n)(\treturn dsi_ctx\.accum_err;)/$1\n\t{\n\t\tu8 shmode = 0xAA;\n\t\tint shret = mipi_dsi_dcs_get_power_mode(pinfo->dsi[0], &shmode);\n\n\t\tpr_info("SHENG_RD: get_power_mode ret=%d val=0x%02x\\n", shret, shmode);\n\t}\n\n$2/;
      ' drivers/gpu/drm/panel/panel-novatek-nt36532e.c

      test "$(grep -c SHENG_RD drivers/gpu/drm/panel/panel-novatek-nt36532e.c)" = "1"
      # BACKLIGHT TX DETECTOR: TESTED AND REJECTED.
      #
      # Plan was to use "send DCS 0x51 0x00 0x00, watch the backlight go
      # dark" as a zero-instrumentation proof that U-Boot's DCS traffic
      # reaches the DDIC. Calibrated it here first, on the system whose
      # transmit path is proven (same boot: get_power_mode returned 0x9e).
      #
      # Result: the command was demonstrably sent to a panel that
      # demonstrably receives, and the backlight did not change
      # (bl_power=0, brightness=1800, screen rendering normally). So 0x51
      # does NOT gate the KTZ8866 on this board -- it is in I2C-brightness
      # mode and the DDIC's PWM output is ignored. The detector is invalid;
      # patch removed.
      #
      # Note the panel driver's own comment is misleading here:
      #   mipi_dsi_dcs_write_seq_multi(&dsi_ctx, 0x51, 0x0f, 0xff);
      #     //Set brightness(controls power output to ktz8866 chips)
      # It does not, in this configuration.


      # BREAK-LINUX PROBE: is the DSI PHY's OWN analog supply load-bearing?
      #
      # State of the evidence when this was written:
      #   * Every documented register on BOTH PHYs matches a rendering
      #     Linux -- PHY0 CMN 124/124 and lane+PLL 412, PHY1 CMN 123/124
      #     and lane 160/160. The single exception is bit 0 of CMN 0x144,
      #     which does not appear in the kernel's own register XML at all.
      #   * The DSI host (176/176), the DPU, DISPCC, VBIF and MDSS all
      #     match by full write-trace diff.
      #   * U-Boot's INTF frame counter advances at ~146fps against a
      #     144Hz panel, so the whole clock tree is right.
      #   * SHENG_RD proved a DCS read WORKS on this bonded link: Linux
      #     gets ret=0 val=0x9e (booster on, sleep out, normal mode,
      #     display on). U-Boot issuing the same read on the same host
      #     gets an all-zero RDBK_DATA0 on BOTH trigger patterns with
      #     CMD_MODE_EN confirmed asserted.
      #   * And TX specifically is what fails: if our commands reached the
      #     DDIC, the panel would be configured, and the earlier
      #     SHENG_NOINIT test (Linux skipping its own init on a panel
      #     U-Boot had just programmed) would have rendered. It was black.
      #
      # So: the digital side is provably perfect and nothing reaches the
      # wire. That is the signature of an ANALOG problem. The D-PHY's own
      # supply is vdds = vreg_l1e_0p88. U-Boot does vote it (ldoe1, 880mV)
      # but an RPMh vote is sent as an RSC/TCS command, not an MMIO write,
      # so the only local confirmation is a TCS ack -- there is no VRM
      # register to read back and this vote has never been verifiable.
      #
      # An underpowered analog rail with a healthy digital rail explains
      # every symptom exactly: PLL locks, status registers read correct,
      # lanes read as driven, frames stream -- and the pads never swing to
      # valid differential levels, so the DDIC hears nothing.
      #
      # Ask Linux. Skip regulator_bulk_enable() for the PHY supplies only,
      # and judge with the READ rather than by eye, which is binary:
      #   read still 0x9e -> vdds is on regardless of who votes it; the
      #     rail is exonerated and U-Boot's vote is not the problem.
      #   read returns nothing -> we have reproduced U-Boot's exact failure
      #     mode in Linux by removing one single thing, and the unverifiable
      #     RPMh vote for ldoe1 becomes the prime suspect for the whole bug.
      # ANSWERED, AND REVERTED -- leaving it in was a mistake worth naming.
      # Result: Linux still read the panel at 0x9e and still rendered, so
      # vdds is on regardless of who votes for it and U-Boot's ldoe1 vote is
      # exonerated (same outcome as the earlier vddio probe).
      #
      # But the patch stayed in the tree for several later experiments, and
      # it is NOT side-effect free: skipping regulator_bulk_enable() while
      # leaving regulator_bulk_disable() in place makes every PHY disable
      # fail with -EIO ("Failed to disable vdds"), so the regulator refcount
      # drifts further out of step on each enable/disable cycle. That is a
      # very plausible cause of the flakiness those experiments then
      # measured -- bring-ups alternating pass/fail and DCS transfers timing
      # out with -110 under repeated blank/unblank. Linux was not a clean
      # oracle while this was applied; any conclusion drawn from repeated
      # cycling during that window has to be re-checked on a clean kernel.

      # DID U-BOOT'S COMMANDS EVER REACH THE DDIC? -- unconfounded.
      #
      # The claim "U-Boot's init does not configure the panel" rests on the
      # SHENG_NOINIT test: U-Boot configures the panel, Linux skips its own
      # reset+init, screen stayed black. But that test needs U-Boot's
      # teardown disabled so its state survives -- and this project's own
      # source note says disabling the teardown "breaks Linux's own render"
      # by itself. Black was therefore guaranteed either way, and the
      # conclusion does not follow. Everything downstream of it inherited
      # that flaw.
      #
      # Ask the panel instead of asking the screen. get_power_mode reports
      # sleep-out and display-on as live DDIC state, so if U-Boot's
      # exit_sleep_mode + set_display_on actually landed, the panel still
      # says so when Linux boots -- no rendering involved, and the
      # teardown/render confound is irrelevant because the READ is the
      # instrument.
      #
      # Read it at the top of nt36532e_prepare(), after the supplies are
      # claimed but BEFORE nt36532e_reset() wipes the DDIC's state. Pair
      # with SHENG_SKIP_TEARDOWN=1 in U-Boot so the panel is handed over
      # still powered and un-reset.
      #
      #   sleep-out/display-on bits set (~0x9c/0x9e) -> U-Boot's DCS
      #     traffic DOES reach the DDIC. TX is fine, fact (b) was an
      #     artefact, and the fault is downstream in the video/DSC path.
      #   display-off / sleep-in (e.g. 0x08) or an error -> the panel is in
      #     its cold post-reset state, U-Boot genuinely never configured it,
      #     and TX is confirmed dead independently of the old test.

      # DIFF A FAILING BRING-UP AGAINST A SUCCEEDING ONE (SPEC.md task #5).
      #
      # With SHENG_SKIP_TEARDOWN=1 in U-Boot, one Linux boot performs the
      # same bring-up twice with opposite outcomes:
      #   [  0.915] SHENG_RD: get_power_mode ret=-61        <- FAILED
      #   [118.078] SHENG_RD: get_power_mode ret=0 val=0x9e <- SUCCEEDED
      # Same kernel, same panel, same code path. The ONLY variable is the
      # hardware state each pass inherited: pass 1 starts on top of
      # U-Boot's live controller, pass 2 starts from Linux's own full
      # disable. Diffing the state each pass inherits therefore names
      # exactly which registers separate "this bring-up will work" from
      # "this bring-up will fail" -- which is precisely what U-Boot has to
      # reproduce, and what no amount of end-state sweeping could reveal.
      #
      # Dump immediately before dsi_timing_setup(): link clocks are up and
      # pinctrl is set, but nothing has been written to the DSI config yet
      # and dsi_sw_reset() has not run, so this is the inherited state.
      # Same idea for the PHY, sampled before cfg->ops.enable() touches it.
      #
      # Both are tagged with a pass counter so the two invocations can be
      # told apart, and dumped as hex so they can be diffed mechanically
      # rather than eyeballed. log_buf_len=8M is already on the cmdline,
      # so volume is not a concern.


      # UART-over-USB-C REVERTED. sheng's debug UART is GPIO26/27 (healthy,
      # verified by driving them as GPIOs and reading back), but neither
      # Xiaomi's vendor DT nor mainline routes it to the USB-C connector,
      # and the FSA4480 has no UART path -- only DP AUX and headset. So
      # enabling uart7 bought nothing, and it was the only Linux-side
      # variable introduced around the time the DRM master stopped binding.
      # Removed to eliminate it as a suspect.


      # QUIET THE TOUCHSCREEN DRIVER (serial console hygiene).
      #
      # nt36xxx.h defines NVT_LOG() as pr_err(), so routine per-boot
      # chatter ("THP stylus scanning mode", "passive capture enabled")
      # arrives at KERN_ERR and is not filtered by loglevel=4. It floods
      # the serial console we use as our only debug channel. NVT_ERR stays
      # at pr_err; only the informational macro is demoted.
      perl -0777 -pi -e '
        s/(#define NVT_LOG\(fmt, args\.\.\.\)\s*)pr_err/$1pr_debug/;
      ' drivers/input/touchscreen/nt36532e/nt36xxx.h

      # REGULATOR HANDOFF PROBE REMOVED -- inconclusive by construction.
      # regulator_is_enabled() on an RPMh VRM returns vreg->enabled, a
      # CACHED value initialised to -EINVAL, so it reports what the Linux
      # driver has done rather than the hardware state. It read -22 for
      # vddio, i.e. "never touched", which tells us nothing about whether
      # U-Boot's vote landed. Replaced by the SHENG_NOVDDIO probe above,
      # which asks the question behaviourally instead.
      # Result: with this kernel skipping its own panel bring-up and U-Boot
      # skipping its teardown, Linux's known-good video path rendered
      # NOTHING on a panel configured solely by U-Boot. So U-Boot's 87-command
      # init + PPS does not configure the DDIC. Kernel restored to normal
      # panel bring-up so it renders again and can act as the oracle.
    '';
    installPhase = "cp -r . $out";
  };

  version = "7.2.0-sheng";

  # The real, complete base config (see note above) -- pinned to the
  # debian-sheng commit that last touched it as of 2026-08-18. Re-pin
  # periodically:
  #   curl -s https://api.github.com/repos/ianchb/debian-sheng/commits/master | jq -r .sha
  baseConfig = fetchurl {
    url = "https://raw.githubusercontent.com/ianchb/debian-sheng/940232a99ef3d5b7c3e7308a0ca367a809dcc799/sm8550.config";
    hash = "sha256-XEBixKV1QLAxQRtlK6cgKVXm3uarahL+dnr5MiurdI4=";
  };

  # Our own additions on top of the known-working base config:
  # - USB ConfigFS ACM/serial gadget + legacy USB_G_SERIAL: upstream
  #   sm8550.config doesn't enable either. USB_G_SERIAL is =m and is
  #   loaded on demand by services.shengSerialConsole.enable, which is
  #   off by default (see modules/serial-console.nix).
  # - GPIO_SHARED_PROXY=y (was =m upstream): matches the locally
  #   confirmed-working sm8550.config.
  # - TYPEC_MUX_PS5169 disabled: drivers/usb/typec/mux/ps5169.c at this
  #   commit fails to compile (missing gpio/consumer.h include, a real
  #   upstream source bug). Not needed for display/console/storage.
  #
  # DRM_MSM: reverted back to upstream's default CONFIG_DRM_MSM=y (was
  # TEMPORARILY disabled for a since-completed cont_splash investigation
  # -- see hardware.nix's getty@tty1 comment for the matching half of
  # that experiment, also due for revert). DRM_MSM is the driver that
  # actually claims and drives this panel; disabling it left "no display
  # driver left for anything past the console" by the disabling commit's
  # own admission. Every "no backlight"/"no framebuffer" symptom chased
  # in SPEC.md's task #5 log under this NixOS build traces back to this
  # one leftover debug toggle, not a hardware fault or anything in
  # U-Boot's own driver work.
  ourConfigFragment = builtins.toFile "sheng-extra.config" ''
    CONFIG_USB_CONFIGFS_ACM=y
    CONFIG_USB_CONFIGFS_SERIAL=y
    # =m, NOT =y. Built in, this auto-binds the UDC at boot, which pins
    # the Type-C port in peripheral mode for the life of the system --
    # no hubs, no keyboards, no DisplayPort alt mode, and no way to turn
    # it off short of a kernel rebuild. As a module it loads only when
    # services.shengSerialConsole.enable asks for it.
    CONFIG_USB_G_SERIAL=m
    CONFIG_GPIO_SHARED_PROXY=y
    # ENABLED (was "is not set") -- this is why the DRM master stopped
    # binding and Linux went black.
    #
    # sm8550-xiaomi-sheng.dts declares typec-retimer@28 as
    # compatible = "parade,ps5169" with BOTH orientation-switch and
    # retimer-switch. With the driver disabled, /sys/bus/i2c/devices/3-0028
    # exists with no driver bound and nothing in the system provides a
    # retimer-switch, so:
    #
    #   pmic_glink_altmode  -> "failed to acquire retimer-switch for port: 0"
    #   aux_bridge          -> "failed to acquire drm_bridge"
    #   ae90000.displayport-controller -> deferred forever
    #   msm_drm component master -> never completes
    #   => no card0, no fb0, no panel driver, touchscreen stuck at -EPROBE_DEFER
    #
    # msm_drm binds all its components or none, so an unprobeable DP
    # controller takes the whole display stack down with it -- which
    # presents as "the panel is black" and looks exactly like the U-Boot
    # bug we are actually chasing. The driver (drivers/usb/typec/mux/ps5169.c)
    # is present in this tree; it just was never enabled.
    CONFIG_TYPEC_MUX_PS5169=y
    # TEMPORARY (SPEC.md task #5 log): /dev/mem's default strict-devmem
    # policy blocks reading "System RAM" resource ranges (only allows
    # MMIO/reserved regions), confirmed via a live PermissionError
    # walking the MDSS SMMU context bank's TTBR0-rooted page table --
    # needed to find what physical address Linux's own dma_base=0x1000
    # IOVA (captured via the SHENG_TRACE dsi_host.c instrumentation)
    # actually resolves to, ground-truth for U-Boot's own SMMU mapping.
    # CONFIG_STRICT_DEVMEM is not set
    # CONFIG_IO_STRICT_DEVMEM is not set
  '';

  configfile = stdenv.mkDerivation {
    pname = "sheng-kernel-config";
    inherit version src;
    nativeBuildInputs = [ flex bison bc perl python3 elfutils openssl ncurses ];
    depsBuildBuild = [ buildPackages.stdenv.cc ];

    dontConfigure = true;
    dontBuild = true;

    installPhase = ''
      runHook preInstall

      export ARCH=arm64
      export KCONFIG_NOTIMESTAMP=1

      cp ${baseConfig} .config
      make olddefconfig

      ./scripts/kconfig/merge_config.sh -O . -m .config ${ourConfigFragment}
      make olddefconfig

      cp .config "$out"

      runHook postInstall
    '';
  };
  # Everything NixOS/linuxPackagesFor might pass via .override {...}
  # (kernelPatches, features, ...) that isn't one of this file's own
  # build-only inputs -- forward it through untouched.
  passthroughArgs = builtins.removeAttrs args [
    "fetchFromGitHub"
    "fetchurl"
    "linuxManualConfig"
    "buildPackages"
    "flex"
    "bison"
    "bc"
    "perl"
    "python3"
    "elfutils"
    "openssl"
    "ncurses"
  ];
in
linuxManualConfig (passthroughArgs // {
  inherit lib stdenv version src configfile;

  # sm8550.config sets CONFIG_LOCALVERSION="-sm8550", so the real
  # kernelrelease string is 7.2.0-sm8550, not 7.2.0-sheng.
  modDirVersion = "7.2.0-sm8550";

  allowImportFromDerivation = true;

  extraMeta = {
    branch = "sheng-7.2.0";
    description = "Mainline kernel for the Xiaomi Pad 6S Pro (sheng, SM8550P)";
  };
})
