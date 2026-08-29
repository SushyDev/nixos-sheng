# Mainline kernel for the Xiaomi Pad 6S Pro (sheng, SM8550P), tracking
# ianchb/sm8550-mainline.
#
# The base config is debian-sheng's repo-root sm8550.config, NOT
# sm8550-mainline's in-tree arch/arm64/configs/sm8550.config -- same name,
# but the in-tree one is a fragment meant to be merged onto defconfig, and
# using it directly yields a kernel with no EXT4_FS and no boot.
{
  lib,
  stdenv,
  fetchFromGitHub,
  fetchurl,
  linuxManualConfig,
  buildPackages,
  flex,
  bison,
  bc,
  perl,
  python3,
  elfutils,
  openssl,
  ncurses,
  ...
}@args:

let
  rawSrc = fetchFromGitHub {
    owner = "ianchb";
    repo = "sm8550-mainline";
    rev = "e87ae95664efe1c616f13be63f051e86ad9b762e";
    hash = "sha256-EuJiqO7MpGO+Voi6/1euBXyS8/2FzGLibhvDFmeSzeM=";
  };

  # Debug instrumentation for the U-Boot DSI work.
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

      perl -0777 -pi -e '
        s/(\tdrm_dsc_pps_payload_pack\(&pps, &pinfo->desc->dsc\);\n)/$1\tprint_hex_dump(KERN_INFO, "SHENG_PPS: ", DUMP_PREFIX_OFFSET, 16, 1, &pps, sizeof(pps), false);\n/;
      ' drivers/gpu/drm/panel/panel-novatek-nt36532e.c

      test "$(grep -c SHENG_PPS drivers/gpu/drm/panel/panel-novatek-nt36532e.c)" = "1"

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

      perl -0777 -pi -e '
        s/(#include "dpu_hw_intf\.h"\n)/$1#include <linux\/ktime.h>\n/;
        s/(\tstruct dpu_hw_blk_reg_map \*c = &intf->hw;\n\t\/\* Note: Display interface select is handled in top block hw layer \*\/\n)/$1\tpr_info("SHENG_SEQ: intf_timing_engine idx=%d enable=%d ktime=%lld\\n", intf->idx, enable, ktime_get_ns());\n/;
      ' drivers/gpu/drm/msm/disp/dpu1/dpu_hw_intf.c

      test "$(grep -c SHENG_SEQ drivers/gpu/drm/msm/disp/dpu1/dpu_hw_intf.c)" = "1"

      perl -0777 -pi -e '
        s/(static inline void dsi_write\(struct msm_dsi_host \*msm_host, u32 reg, u32 data\)\n\{\n)(\twritel\(data, msm_host->ctrl_base \+ reg\);\n)/$1\t{\n\t\tstatic int sheng_w_n;\n\t\tif (sheng_w_n < 4000) {\n\t\t\tsheng_w_n++;\n\t\t\tpr_info("SHENG_W id=%d off=0x%03x val=0x%08x\\n", msm_host->id, reg, data);\n\t\t}\n\t}\n$2/;
      ' drivers/gpu/drm/msm/dsi/dsi_host.c

      test "$(grep -c SHENG_W drivers/gpu/drm/msm/dsi/dsi_host.c)" = "1"

      perl -0777 -pi -e '
        s/(\tif \(cfg_hnd->ops->tx_buf_put\)\n)/\t{\n\t\tstatic int sheng_c_n;\n\t\tif (sheng_c_n < 200) {\n\t\t\tsheng_c_n++;\n\t\t\tprint_hex_dump(KERN_INFO, "SHENG_C: ", DUMP_PREFIX_NONE, 32, 1, data, len < 20 ? len : 20, false);\n\t\t}\n\t}\n$1/;
      ' drivers/gpu/drm/msm/dsi/dsi_host.c

      test "$(grep -c SHENG_C drivers/gpu/drm/msm/dsi/dsi_host.c)" = "1"

      # The macro is defined after the helper, so the helper gets the real one.
      perl -0777 -pi -e '
        s/(#include "dsi_phy_7nm\.xml\.h"\n)/$1\nstatic inline void sheng_phy_wl(u32 val, void __iomem *addr)\n{\n\tstatic int sheng_p_n;\n\tif (sheng_p_n < 3000) {\n\t\tsheng_p_n++;\n\t\tpr_info("SHENG_P pg=%lx off=0x%03lx val=0x%08x\\n", (unsigned long)addr >> 12, (unsigned long)addr & 0xfff, val);\n\t}\n\twritel(val, addr);\n}\n#define writel(v, a) sheng_phy_wl((v), (a))\n/;
      ' drivers/gpu/drm/msm/dsi/phy/dsi_phy_7nm.c

      test "$(grep -c SHENG_P drivers/gpu/drm/msm/dsi/phy/dsi_phy_7nm.c)" = "1"

      perl -0777 -pi -e '
        s/(\twritel_relaxed\(val, c->blk_addr \+ reg_off\);\n)/\t{\n\t\tstatic int sheng_d_n;\n\t\tif (sheng_d_n < 4000) {\n\t\t\tsheng_d_n++;\n\t\t\tpr_info("SHENG_D blk=%05lx off=0x%03x val=0x%08x %s\\n", (unsigned long)c->blk_addr & 0xfffff, reg_off, val, name);\n\t\t}\n\t}\n$1/;
      ' drivers/gpu/drm/msm/disp/dpu1/dpu_hw_util.c

      test "$(grep -c SHENG_D drivers/gpu/drm/msm/disp/dpu1/dpu_hw_util.c)" = "1"

      # noinit/noreset keep the supplies on, or the unused-regulator cleanup
      # powers the panel down and a black screen proves nothing.
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

      perl -0777 -pi -e '
        s/(\tmipi_dsi_dcs_set_display_on_multi\(&dsi_ctx\);\n\n)(\treturn dsi_ctx\.accum_err;)/$1\n\t{\n\t\tu8 shmode = 0xAA;\n\t\tint shret = mipi_dsi_dcs_get_power_mode(pinfo->dsi[0], &shmode);\n\n\t\tpr_info("SHENG_RD: get_power_mode ret=%d val=0x%02x\\n", shret, shmode);\n\t}\n\n$2/;
      ' drivers/gpu/drm/panel/panel-novatek-nt36532e.c

      test "$(grep -c SHENG_RD drivers/gpu/drm/panel/panel-novatek-nt36532e.c)" = "1"

      perl -0777 -pi -e '
        s/(#define NVT_LOG\(fmt, args\.\.\.\)\s*)pr_err/$1pr_debug/;
      ' drivers/input/touchscreen/nt36532e/nt36xxx.h
    '';
    installPhase = "cp -r . $out";
  };

  version = "7.2.0-sheng";

  baseConfig = fetchurl {
    url = "https://raw.githubusercontent.com/ianchb/debian-sheng/940232a99ef3d5b7c3e7308a0ca367a809dcc799/sm8550.config";
    hash = "sha256-XEBixKV1QLAxQRtlK6cgKVXm3uarahL+dnr5MiurdI4=";
  };

  ourConfigFragment = builtins.toFile "sheng-extra.config" ''
    CONFIG_USB_CONFIGFS_ACM=y
    CONFIG_USB_CONFIGFS_SERIAL=y
    # =m, not =y: built in it auto-binds the UDC at boot, pinning the Type-C
    # port in peripheral mode for the life of the system.
    CONFIG_USB_G_SERIAL=m
    CONFIG_GPIO_SHARED_PROXY=y
    # Without this the ps5169 retimer never binds, the DP controller defers
    # forever, and msm_drm -- all components or none -- never completes.
    CONFIG_TYPEC_MUX_PS5169=y
    # Temporary: strict-devmem blocks the MDSS SMMU page-table walks.
    # CONFIG_STRICT_DEVMEM is not set
    # CONFIG_IO_STRICT_DEVMEM is not set
  '';

  configfile = stdenv.mkDerivation {
    pname = "sheng-kernel-config";
    inherit version src;
    nativeBuildInputs = [
      flex
      bison
      bc
      perl
      python3
      elfutils
      openssl
      ncurses
    ];
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
linuxManualConfig (
  passthroughArgs
  // {
    inherit
      lib
      stdenv
      version
      src
      configfile
      ;

    # sm8550.config sets CONFIG_LOCALVERSION="-sm8550", so kernelrelease is
    # 7.2.0-sm8550, not 7.2.0-sheng.
    modDirVersion = "7.2.0-sm8550";

    allowImportFromDerivation = true;

    extraMeta = {
      branch = "sheng-7.2.0";
      description = "Mainline kernel for the Xiaomi Pad 6S Pro (sheng, SM8550P)";
    };
  }
)
