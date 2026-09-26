# Development

Working on `nixos-sheng`: the layout, the scripts, how to get diagnostics off a device
with no serial port, and the things that have already cost someone a recovery.

If you are just installing, you want [README.md](README.md) instead.

---

## The workspace

Development happens in a workspace directory that holds this repository next to its
siblings. One devenv shell, defined here, serves all of them:

```
sheng-development/
├── .envrc           `source_env nixos`, so every subdirectory gets the shell
├── sheng-devkey     SSH key the device trusts (see below)
├── nixos/           this repository; devenv.nix lives here
├── u-boot/          SushyDev/u-boot, branch xiaomi-sheng
├── kernel/          optional sm8550-mainline checkout, for --local-kernel
└── references/      read-only upstream clones, from dev/references.txt
```

From scratch:

```sh
mkdir sheng-development && cd sheng-development
git clone git@github.com:SushyDev/nixos-sheng.git nixos
cd nixos && devenv shell     # or: direnv allow
workspace-init               # clones u-boot, installs ../.envrc, syncs references
sheng-help                   # the command list
```

The shell's toolchain (Zig, the aarch64 cross GCC) comes from `flake.lock`'s nixpkgs,
not devenv's, so the fast local U-Boot build and `nix build .#u-boot` compile with the
same Zig. Zig breaks its language between minor versions, so this matters.

### The two loops

**U-Boot**, natively on the host, incremental, seconds per iteration:

```sh
uboot build          # ../u-boot/.output -> nixos/out/boot.img
flash-uboot          # over SSH to a running device, both slots, reboot
# or: fastboot-flash, from fastboot mode
```

`uboot build` prints the image size as a delta against the previous build (ABL's
budget is roughly 1 MiB) and warns when `sheng.b=` was not bumped.
`uboot build --debug` builds into `.output-debug` with
`CONFIG_VIDEO_SHENG_MDSS_DEBUG=y`, without touching the defconfig.
`uboot menuconfig` / `uboot savedefconfig` round-trip the defconfig.

**NixOS**, in the aarch64-linux Docker builder, whose `/nix` volume keeps the kernel:

```sh
builder fetch nixos                  # -> nixos/out/sheng-rootfs.sparse.img
builder fetch u-boot --local-uboot   # the reproducible U-Boot, from ../u-boot as on disk
builder fetch nixos --local-kernel   # kernel from ../kernel, committed state of its branch
builder shell                        # a shell inside, in this directory
```

The builder mounts the whole workspace read-only at the host's own path, so flake
paths and `--override-input` mean the same thing inside and out.

`--local-kernel` reads the checkout's current branch from git objects rather than the
worktree: on macOS's case-insensitive filesystem the kernel's netfilter header pairs
(`xt_CONNMARK.h`/`xt_connmark.h`) collide, so a worktree copy would be silently wrong. Commit first.

### The kernel

The kernel source and its base config are flake inputs, `kernel-src`
(`github:ianchb/sm8550-mainline/<tag>`) and `kernel-config` (debian-sheng at a commit).
`version` and `modDirVersion` are read from the tree's `Makefile` and the config's
`CONFIG_LOCALVERSION`, so moving kernels is editing those two URLs, `nix flake lock`,
and checking that `packages/kernel/patches/` still applies.

### References

`refs sync` clones or fast-forwards everything in `dev/references.txt` into
`../references/<owner>/<repo>` and prints the new commits. `refs status` shows where each
one is. Add a line to track another repository. Non-git material (stock firmware
images, GPT dumps) goes in `../references/vendor/`, by hand.

---

## Repository layout

```
nixos/
├── flake.nix        outputs: packages, apps, nixosModules, overlays, lib
├── overlay.nix      adds shengKernel, shengPackages and shengSddm to nixpkgs
├── lib/             shengSystem — the entry point for downstream flakes
├── modules/         the driver layer, options under `sheng.*` (see table below)
│   ├── hardware/    the device itself, plus vendor daemons per subsystem
│   ├── boot/        extlinux + U-Boot menu, rootfs image, A/B slot, store registration
│   ├── system/      opt-in or self-gating extras: greeter, ccache, performance, serial
│   └── bringup.nix  host policy for the reference image; not imported by default.nix
├── packages/
│   ├── u-boot/      buildUBoot + mk-boot-img -> boot.img
│   ├── kernel/      linuxManualConfig; every file in patches/ is applied, in order
│   └── vendor/      one directory per vendor userspace package
├── scripts/         host tools: `nix run .#<name>`, and on the devenv shell's PATH
├── dev/             references.txt, the workspace .envrc template
├── devenv.nix       the workspace shell
└── docker/          the aarch64 build container
```

| Module | Switch | Does |
|---|---|---|
| `hardware/default.nix` | — | Kernel, device tree, kernel params, root filesystem, firmware. Hardware only — no users, no daemons, no hostname. |
| `hardware/audio.nix` | `sheng.audio.enable` | The HiFi UCM verb, bound to the card's device unit; speaker channels follow orientation; WirePlumber rules if the host runs WirePlumber. |
| `hardware/camera.nix` | `sheng.camera.enable` / `.qtGstreamerBackend` | The libcamera monitor, and optionally Qt's GStreamer backend. |
| `hardware/sensors.nix` | `sheng.vendor.enable` | fastrpc sensor PD (gated on SSC answering), libssc, iio-sensor-proxy. |
| `hardware/qtee.nix` | `sheng.vendor.enable` | qteesupplicant, fingerprint via fprintd, keyboard cover authentication. |
| `hardware/input.nix` | `sheng.vendor.enable` | Touch (THP), pen status, keyboard fold-angle and mic-mute helpers. |
| `hardware/power.nix` | — / `sheng.vendor.enable` | Pins `SuspendState=mem` (s2idle hangs this device); MiPPS 120 W authentication and charger-mode screen. |
| `hardware/wireless.nix` | `sheng.factoryAddresses.enable` | Factory Wi-Fi/Bluetooth addresses from `persist`, mounted read-only. |
| `boot/extlinux.nix` | — | Fork of `generic-extlinux-compatible` that also writes U-Boot's `sheng-bootmenu.env`, one entry per generation and specialisation (script: `install-boot.sh`). |
| `boot/image.nix` | — | `system.build.shengImage`: ext4 + Android sparse rootfs, and `sheng.rootfs.etcNixosSource`. |
| `boot/slot.nix` | `sheng.boot.markSuccessful` | `qbootctl -m` once up. |
| `boot/nix-bootstrap.nix` | `sheng.boot.registerStore` | First-boot store registration. |
| `system/greeter.nix` | `sheng.greeter.enable` | The SDDM fixes, each gated on the host having enabled SDDM (and KWin, and fprintd). |
| `system/build-cache.nix` | `sheng.buildCache.enable` (off) | ccache for shengKernel builds on the device. |
| `system/performance.nix` | `sheng.performance.enable` (off; on in the reference image) | zram, systemd-oomd, a deprioritised nix-daemon. |
| `system/serial-console.nix` | `sheng.serialConsole.enable` (off) | The ttyGS0 gadget console. |
| `bringup.nix` | **not imported by `default.nix`** | Root password, autologin, sshd, NetworkManager, mDNS — the host half of this repo's own reference image. |

The split is the point: `default.nix` is a driver layer and configures nothing about how
the machine is used. Workarounds that touch user-visible services are gated on the host
having chosen the thing they fix — `greeter.nix` contributes nothing without SDDM, the
WirePlumber rules nothing without WirePlumber, the Bluetooth address nothing without
Bluetooth, and `overlay.nix` exposes the patched SDDM as `shengSddm` rather than replacing
`qt6Packages.sddm-unwrapped` for everyone.

The old `services.sheng*` option names still work, with a deprecation warning.

**U-Boot lives in a different repository.** It is pinned as the non-flake input
`u-boot-src` (`github:SushyDev/u-boot`, branch `xiaomi-sheng`); `uboot build` and
`builder fetch u-boot --local-uboot` use the workspace's `../u-boot` instead.

`CONFIG_TYPEC_MUX_PS5169=y` in the kernel fragment is not optional: without the retimer
`mdss_dp0` `EPROBE_DEFER`s forever and takes the whole msm KMS aggregate down with it. The
config build fails if any line of the fragment does not survive `olddefconfig`.

---

## Getting a shell on the device

In the devenv shell `SHENG_KEY` points at the workspace's **`sheng-devkey`**. Outside it,
every script locates the project by walking up to four parent directories looking for a
file named `sheng-devkey` — an SSH private key whose public half is authorised on the
device. Put it at the repository root, or point `SHENG_KEY` somewhere else. The discovered
root is also where the IP cache lands (`SHENG_IP_CACHE`, default `.sheng-ip`).

> **Note** — the shipped image bakes **no** `authorizedKeys`, so on a freshly flashed
> device you have to install the public key over the serial console first.

### Over the network

```sh
nix run .#find-sheng            # prints the device IP
```

It tries the cache first, then sweeps the `/24` derived from `ipconfig getifaddr en0` in
parallel with `nc -z … 22`, identifying a sheng by the presence of
`/dev/disk/by-partlabel/boot_a`. The device takes a new DHCP lease on every boot, which is
why the cache exists and why it goes stale.

The sweep is macOS-specific (`ipconfig`), falling back to `192.168.2.1`.

> **Note** — when it finds nothing it exits `1` and prints nothing at all. That is not a
> hang; it means the device is off, on another subnet, or not yet accepting your key.

### Over the USB serial gadget

> **This is opt-in.** `sheng.serialConsole.enable` defaults to `false`, because
> binding the g_serial gadget to the UDC holds the Type-C port in peripheral mode and kills
> USB host mode with it. An image built without it has no `ttyGS0` at all — `exec`,
> `read-blackbox` and `capture-linux-dpu` all depend on this, so a debugging image wants:
>
> ```nix
> sheng.serialConsole.enable = true;
> ```
>
> On a stock image the equivalent way in is a USB keyboard on tty1, which autologins.

With it enabled, `ttyGS0` has root autologin. In the devenv shell, `serial` starts the
`tio` bridge (first `/dev/cu.usbmodem*`, or pass the device):

```sh
serial &
exec 'df -h /'
```

> **Warning** — remove a stale `/tmp/nixos-socket` first. The socket outlives the `tio`
> process, and `exec` silently returns nothing against a dead one, which reads exactly like
> a hung device.

---

## Scripts

All are `nix run .#<name>`, or run directly out of `nixos/scripts/`.

| Script | Usage | Needs |
|---|---|---|
| `find-sheng` | `find-sheng` | network |
| `exec` | `exec '<command>'` | `tio` bridge on `/tmp/nixos-socket` |
| `flash-uboot` | `flash-uboot [boot.img]` | SSH, device running Linux |
| `fastboot-flash` | `fastboot-flash [boot.img]` | fastboot mode |
| `flash-rootfs` | `flash-rootfs [sheng-rootfs.sparse.img]` | fastboot mode |
| `soak` | `soak [count]` (default 15) | SSH |
| `sheng-mdss-status` | `sheng-mdss-status` | SSH |
| `read-blackbox` | `read-blackbox [out.txt]` | `exec` bridge |
| `capture-linux-dpu` | `capture-linux-dpu [blackbox.txt]` | `exec` bridge |
| `builder` | `builder [up\|down\|status\|shell\|run <cmd>\|build\|fetch <attr> [--local-uboot] [--local-kernel]]` | docker |
| `uboot` | `uboot [build [--debug]\|menuconfig\|savedefconfig\|clean]` | a U-Boot checkout |
| `mk-boot-img` | `mk-boot-img <u-boot-dtb.bin> <u-boot.dtb> <boot.img>` | — |
| `refs` | `refs [sync\|status]` | network |
| `serial` | `serial [/dev/cu.usbmodemN]` (devenv only) | USB |

Both `[boot.img]` defaults are `$SHENG_OUT/boot.img`; `flash-rootfs` defaults to
`$SHENG_OUT/sheng-rootfs.sparse.img`. `SHENG_OUT` is `nixos/out` in the devenv shell and
`./out` outside it — where both `uboot build` and `builder fetch` put their artifacts, so
the last thing built is what gets flashed.

### `flash-uboot` — reflash without touching a button

`boot_a` and `boot_b` are ordinary GPT partitions and `/` is read-write, so a running
device can rewrite its own bootloader. This is the difference between a two-minute test
cycle and a fastboot dance per build.

It scps the image to `/root/boot-new.img`, then runs a guard on the device that resolves
each `by-partlabel` symlink, verifies `lsblk`'s `PARTLABEL` matches, **rejects any target
that also resolves to `xbl_a xbl_b xbl_config_a xbl_config_b abl_a abl_b`**, size-checks
the partition (32 MiB–512 MiB and larger than the image), `dd`s with `conv=fsync`, then
reads back and compares SHA-256. Then it reboots and clears the IP cache.

Both slots are written, because which one is live is ambiguous.

### `flash-rootfs` — the destructive one

Sniffs the magic first (Android sparse `3aff26ed` at offset 0, or ext4 `53ef` at `0x438`)
and refuses anything else. Requires exactly one fastboot device, and makes you type `wipe`.
The partition name `userdata` is a literal in the script and is never derived from an
argument, so no input can redirect a write to `xbl` or `abl`.

### `soak` and `sheng-mdss-status`

`sheng-mdss-status` decodes `/proc/device-tree/chosen/sheng,mdss-status` once: eleven
stages — `MDSS_RESET GDSC BCM_MM0 DISPCC DSI0_PHY DSI1_PHY DSI_PHY_START DSI_LINK_CLKS
DSI_PANEL DPU PROBE` — where `0` is success, `0x7fffffff` means the stage was never
reached, and anything else is `-errno`. It special-cases the case where at most one stage
ran, reporting that U-Boot inherited ABL's live display and skipped the cold bring-up
entirely.

`soak [count]` is the same read in a reboot loop, rediscovering the IP each time.

---

## Reading diagnostics

This board has **no reachable UART**, and `/dev/mem` at `CONFIG_PRE_CON_BUF_ADDR` returns
`EFAULT` because it is a `no-map` reserved region — so U-Boot's pre-console buffer is not
readable from Linux at all. Three side channels exist instead.

### 1. `/chosen` properties — always compiled in

Published by `ft_board_setup()` on every boot, readable over plain SSH. This is the first
thing to look at, always.

```sh
cat /proc/device-tree/chosen/sheng,display-diag
cat /proc/device-tree/chosen/sheng,boot-timing
```

| Property | Contents |
|---|---|
| `sheng,mdss-status` | 11 × s32, one per bring-up stage (see above) |
| `sheng,ktz8866-status` | 2 × s32, one per backlight/bias chip |
| `sheng,uclass-get-device-ret` | Distinguishes "no video device bound" from "bound, probe failed" |
| `sheng,boot-timing` | `entry= <mark>= … total= abl= relocdone= backlight= handover[bl/avdd/avee/rst/blregs]` |
| `sheng,display-diag` | `fastpath= probes= panel_init= gdsc[] clkfail= status0= fifo= lane= ackerr= timeout= pll_l= frames=N->M pm= dsi[retries/failidx/failrc]` |
| `sheng,xbl-log`, `sheng,abl-log` | Tails scraped out of XBL's and ABL's own log regions, which Linux cannot map |
| `sheng,pon` | PMIC PON register dump (HLOS `@13xx` + PBS `@08xx`, `0x00`–`0x1f`) |
| `sheng,mdss-log` | The `(tag, value)` ring — **debug builds only** |

### 2. The blackbox — ~512 KB of ASCII in DRAM

```sh
nix run .#read-blackbox -- log.txt
```

A ring buffer at `0xa5000000` written by the Zig side and read back through `/dev/mem`.
Its magic (`SHGB`) is written **last**, so a torn log is detectable, and every record is
flushed to the point of coherency, so it survives a hard hang.

It exists because the previous channel was `sheng.*` entries on the kernel command line,
capped at `CONFIG_SYS_CBSIZE = 512` bytes — roughly one question per boot, with register
sweeps reported as "first mismatching offset + count" and the values never visible.

### 3. Boot timing

```sh
cat /proc/device-tree/chosen/sheng,boot-timing
```

The measured breakdown, so nobody re-derives it: **~81 % of the time to backlight-on is
XBL + ABL, before U-Boot's first instruction.** U-Boot's entire contribution is ~1.3 s of
a ~6.9 s boot.

> **Warning** — ABL's own time varies by ~650 ms between boots of the *same* image. That
> jitter is larger than any display-path change is likely to buy, so **never judge a timing
> change by comparing `backlight=` across boots.** Compare the per-stage deltas
> (`panel DCS init`, `panel pwr cycle`), which are stable.

---

## Opting into debug builds

### U-Boot: `CONFIG_VIDEO_SHENG_MDSS_DEBUG`

Off in `sm8550_defconfig`. Turning it on adds `sheng_mdss_debug.c` and
`sheng_mdss_diag.zig`, the `sheng_*` environment dump, and a full register sweep — at the
cost of ~1 s of extra boot delay and many MMIO reads of live display blocks on every boot.

On the Zig side it is compiled out at comptime through a Kconfig-generated `config` module
(`scripts/Makefile.zig`), because `zig build-obj` has no `-D` equivalent.

`uboot build --debug` turns it on for a local build without editing the defconfig. The
Nix package has no knob.

> **Warning — this build rots.** What ships is `=n`, so the `=y` build is never exercised
> by a normal build; it had been broken for three commits before anyone noticed. After
> touching anything shared between `sheng_mdss.c`, `sheng_mdss_debug.c` and the Zig, flip
> it on, build, and flip it back.
>
> Also: with `=n` the macros **discard their arguments**. Never put a side-effecting call
> inside one. This has already cost one latched panel.

### The `sheng.b=<n>` build tag

Carried in `sheng.env`'s `bootrescue` bootargs. **Bump it on every build.** A plain
power-cycle re-runs the *old* image, and without the tag a stale boot is indistinguishable
from a real result — that has cost a full debug cycle before.

```sh
nix run .#exec -- 'tr " " "\n" < /proc/cmdline | grep sheng'
```

---

## Testing recipes

### Did my U-Boot change actually boot?

Bump `sheng.b=`, build, `flash-uboot`, then read the tag back off `/proc/cmdline` with the
command above. If it still shows the old number, you are looking at the old image.

### The panel is black or glitched

1. `nix run .#sheng-mdss-status` — which stage failed, or whether the cold bring-up ran at
   all.
2. `cat /proc/device-tree/chosen/sheng,display-diag` — in particular `probes=`.

> **Warning — `soak` cannot see a rendering glitch.** It checks only the eleven stage
> codes, and a visibly corrupted boot still reports every stage `0`. Worse, if the first
> probe fails, `qcom_late_init()` silently re-runs the *entire* probe, and the retry
> overwrites the stage array with its own success. `soak` called 6/6 boots clean while the
> panel was visibly glitching.
>
> `probes=2` in the diagnostic is what detects the retry, and `panel_init_first=` keeps
> the first attempt's error before the retry masks it. Any "verified over N soak boots"
> claim about a *rendering* bug is worthless.

### Is U-Boot's pipeline configured the same as Linux's?

```sh
nix run .#read-blackbox -- uboot.txt     # after a U-Boot boot
nix run .#capture-linux-dpu -- uboot.txt # on a rendering Linux
```

`capture-linux-dpu` reads the identical DSC/CTL/LM/INTF/PP/MERGE3D/DSI register ranges off
a working system and diffs them mechanically, printing `TOTAL DIFFERENCES`. It exists
because every earlier comparison was done by eye or as "first mismatching offset".

The DSC ranges are the point: the encoder lives at `+0x100` inside the block, so earlier
dumps of `0x80000`–`0x800fc` were comparing an all-zero gap and falsely matching.

### It boots straight into fastboot and stays there

The A/B retry counter ran out. **Do not reboot eight times to test** — read the bits:

```sh
nix run nixpkgs#qbootctl            # both slots
sfdisk --part-attrs /dev/sdX 14     # boot_a
```

Recover with `fastboot set_active b && fastboot reboot`. The UFS disk letter moves between
boots (`sdd`/`sde`/`sdf`), so always resolve through `/dev/disk/by-partlabel/`.

### Changing a panel timing constant

**One knob per flash.** Changing all three at once produced a badly glitched screen that
could not be attributed to any of them, and cost a full round.

| Constant | Where |
|---|---|
| `discharge_ms` | `drivers/video/qualcomm/sheng_mdss.c` |
| `ENABLE_SETTLE_US` | `sheng_mdss_hw.zig` |
| `INIT_CMD_PACING_US` / `PAGE_SWITCH_PACING_US` | `sheng_mdss_hw.zig` |

Each change shows up as a `panel DCS init` or `panel pwr cycle` delta in the timing relay,
so the numbers confirm a cut took effect and only the *screen* needs a human to look at it.

---

## Hazards

> **Never do these.** Each one has already cost a recovery or a debug cycle.

- **Never touch DPU registers in the early ABL-sampling path.** They need the MDP core
  clock and that path only has AHB; the read wedges the bus in exactly the case it was
  meant to detect. Three fastboot recoveries came from this. Liveness comes from DSI0
  `CLK_STATUS` bit 14 at worst, and from the DTB at best.
- **Never enable `CONFIG_OF_LIBFDT_OVERLAY`.** It adds a tenth `lmb_alloc()` in
  `board_late_init()` and grows the DTB 117 KB → 152 KB, which moves allocations onto the
  live framebuffer. Every fixed-address region — framebuffer, DSI DMA scratch, blackbox —
  has to be explicitly `lmb_alloc()`-reserved, and the failure is *intermittent*: a build
  that changes image size by a few kilobytes can land an allocation on the framebuffer with
  no other change.
- **Never add a plain `reset` entry to the boot menu.** A stuck button selects it, the
  board reboots into the menu, and selects it again — only fastboot breaks the loop.
  `rebootfastboot` is the safe terminal equivalent.
- **Never write `xbl*` or `abl*`.** Unrecoverable. `flash-uboot` refuses them by name.
- **The U-Boot image size is a hard budget.** Crossing roughly 1 MB of loaded size collides
  with something ABL still has resident, and `_main`'s first instruction never executes.
  This is why `VIDEO_LOGO` and BMP support are off.
- **Teardown belongs in `board_preboot_os()`, not `board_late_init()`.** The latter
  finishes before `main_loop()`, so the console dies while you are still using it.
- **`CONFIG_ENV_IS_NOWHERE` is set.** There is no saved environment: `saveenv` does
  nothing, and changing anything in `sheng.env` requires a rebuild and a reflash.

---

## Known issues

- `bringup.nix` ships root autologin and a baked root password (`password`) — see
  [README.md](README.md#first-boot).
- The firewall is `mkDefault false`. The kernel now has `nft_fib_inet` and the modules
  select the nftables backend, so it should load; turn it on once that is confirmed.
- Not yet validated on hardware (September 2026): kernel 7.2.6-mac with patches 07/08,
  the factory Wi-Fi/Bluetooth addresses, and the SSC start gate.
