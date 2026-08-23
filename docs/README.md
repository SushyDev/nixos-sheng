# nixos-sheng

NixOS and a U-Boot port for the **Xiaomi Pad 6S Pro 12.4** (`sheng`, Snapdragon 8 Gen 2 / SM8550).

> **Project Status**
> Early but usable. The tablet boots mainline Linux with a working display, backlight,
> sensors, fingerprint reader, keyboard and pen. It needs an **unlocked bootloader**, and
> **installing wipes the device** — dual-boot is not supported. Read
> [Flashing](#flashing) before you start.

---

## What makes this port interesting

Most of the unusual work is in U-Boot. This device has **no reachable UART**, so the
bootloader had to bring up the panel before it could say anything at all — everything
below follows from that.

### Display

- **A native MDSS/DSI/DPU driver for SM8550, written in Zig.** U-Boot had no Qualcomm
  display driver for this SoC family. `sheng_mdss_hw.zig` is ~5,200 lines of register
  sequencing — GDSC, DISPCC PLL0, both DSI PHYs, both DSI hosts, the panel, and the full
  DPU pixel pipeline from cold — compiled as a freestanding aarch64 object and linked in.
  It calls back into U-Boot for `udelay`, `flush_dcache_range` and `timer_get_us`, and
  nothing else.

- **Seamless handover from Xiaomi's bootloader — no black gap.** The headline feature.
  Advertising `/reserved-memory/splash_region` in the DTB — *exact node name, no unit
  address*, because ABL looks it up by path — makes ABL stop blanking the panel ~2 s
  before handover and hand over a **live, streaming** pipeline. U-Boot then *inherits*
  it: it points the video uclass at ABL's framebuffer at `0xb8000000` and touches nothing
  else. No GDSC collapse, no MDSS reset, no panel power-cycle, no 94-command init. The
  Xiaomi logo runs directly into U-Boot's boot menu with no flicker.

  The reverse direction is handled too: `board_preboot_os()` stops the INTF timing engine
  and *then* runs a full teardown, so Linux still receives a quiescent MDSS and brings the
  panel up normally.

- **Panel: nt36532e, 3048×2032 @ 144 Hz, dual bonded DSI, DSC 1.1.** 87 static DCS
  commands plus a 128-byte PPS. `qcom,sync-dual-dsi` mirrors DSI0's writes to DSI1 in
  hardware, so each host carries half the picture. Compression is 8bpc / 8.0bpp in two
  slices of 762×16, kept in sync with the DPU encoder config.

- **Liveness is decided from the DTB, never from hardware.** Asking the DPU "are you
  streaming?" requires clocks that only run *while* it streams, so the probe wedges the
  AHB bus in exactly the case it is meant to detect. U-Boot therefore just checks whether
  the `splash_region` node exists.

- **A console on the panel** (`VIDEO_FONT_16X32`, the largest bitmap font that builds
  under `-mgeneral-regs-only`), since there is nowhere else to print.

- **Backlight and panel bias from two KTZ8866s** on two different GENI wrappers — one of
  them behind a `qcom,geni-se-i2c-master-hub`, which needed a firmware-load fix in
  `qcom_geni.c`. Each chip does two jobs: the LED backlight *and* the ±5.8 V panel bias.

### Boot and input

- **Working buttons in the bootloader.** Volume up / volume down / power drive the boot
  menu. The DTS remaps them to `KEY_UP` / `KEY_DOWN` / `KEY_ENTER`, because
  `button_kbd` passes `linux,code` straight through and `KEY_VOLUMEUP` maps to nothing a
  menu can consume.

- **Per-generation boot menu.** `nixos-rebuild` regenerates
  `/boot/sheng-bootmenu.env`, which U-Boot `env import`s at boot — hush cannot enumerate
  directories, so the list has to be handed to it. Pick any NixOS generation with the
  volume keys. The last entry is always "Reboot to fastboot".

- **Reboot to fastboot, from the menu.** The Android BCB/`misc` handshake is ignored by
  this ABL (measured: it boots straight past `bootonce-bootloader`). The real mechanism is
  an IMEM restart-reason cookie — `0x146aa65c = 0x77665500`, taken from the *stock* DTB —
  plus a **PSCI** reset. `qcom_pshold` does not preserve the reason.

- **Charger insert does not boot the device into Linux.** Stock ABL routes a cable
  insert to offline charging, which this port does not implement, so every plug-in used to
  become a full boot. It is now detected from the PMIC PBS peripheral (PID `0x08`,
  offset `0x15`: bit 7 charger-initiated **and** bit 5 cold-boot, both required, or a warm
  reboot is misread) and parked at `sheng: charging. Press POWER to boot.`

- **Initramfs-less boot.** `boot.initrd.enable = false`; the kernel finds root through its
  own `root=PARTLABEL=userdata`.

- **A/B slot marking.** ABL keeps slot state in GPT attribute bits 48–55 and decrements
  the retry counter on every handoff; plain Linux never sets the "successful" bit, so the
  device eventually refuses to boot. `modules/boot-slot.nix` runs `qbootctl -m` after
  `multi-user.target`.

### System

Vendor userspace works — sensors, fingerprint + QTEE, touch host processing, pen status,
keyboard helper, 120 W charging authentication, ALSA UCM — behind the single switch
`services.shengFirmware.enable`. See [Firmware](#firmware).

### Generic U-Boot bugs fixed along the way

- `start.S` computed the pre-crt0 stack as `_start + image_size + 0x10000`, which moves
  *upwards* as the binary grows. On this board it eventually landed in ABL/TZ memory and
  corrupted the running firmware, and U-Boot never reached `_main`.
- `N_RESERVED_REGIONS` raised 32 → 48. This DTB has 34; the excess were silently dropped,
  leaving unmapped regions as ordinary cacheable RAM.
- The SM8550 CX/MMCX `rpmhpd` descriptors were missing entirely — without MMCX any DPU
  register access hangs the AHB bus forever, and without CX every
  `power-domains = <&rpmhpd RPMHPD_CX>` request (UFS included) silently did nothing.
- `qcom,geni-se-i2c-master-hub` wrappers were missing from the GENI firmware-load scan.

---

## What is not implemented

> **Note**
> - **No USB gadget in U-Boot** — no fastboot and no serial console *from the bootloader*.
>   (`g_serial.use_acm=1` in the boot.img cmdline is for the kernel, which does provide a
>   USB serial console.)
> - **No dual-boot.** Android is overwritten.
> - `iio-sensor-proxy` is currently commented out in `modules/firmware.nix` — one of its
>   patches is fetched from `gitlab.postmarketos.org`, which the aarch64 builder sandbox
>   cannot resolve.

---

## Requirements

> **You need one of:**
> - **Docker** — works on any host (macOS, x86_64 Linux, aarch64 Linux). Recommended.
> - **Nix, with access to an `aarch64-linux` builder.**

Every device-facing output is `aarch64-linux` only and nothing here cross-compiles, so an
x86 or macOS host needs a builder either way. The reason the Docker path exists rather
than a plain remote builder: Determinate Nix's native Linux builder VM has **no network**,
so every fixed-output derivation not already in a binary cache fails to fetch — and this
kernel is source-patched, so it is in no cache.

On the machine that does the flashing you also need `android-tools` (for `fastboot`) and
an **unlocked bootloader**.

---

## Building

Two artifacts come out: **`boot.img`** (U-Boot, flashed to the boot partitions) and
**`sheng-rootfs.sparse.img`** (the NixOS rootfs, flashed to `userdata`).

> **Note** — the rootfs is `sheng-rootfs.sparse.img`, not `userdata.img` or `rootfs.img`.
> Set `sheng.rootfs.keepRawImage = true` if you also want the raw ext4 image to loopback-mount.

### With Docker (recommended)

```sh
git clone https://github.com/SushyDev/nixos-sheng && cd nixos-sheng

nix run .#builder -- up                 # start the aarch64 build container
nix run .#builder -- fetch u-boot       # -> ./result/boot.img
nix run .#builder -- fetch nixos        # -> ./result/sheng-rootfs.sparse.img
```

| Command | What it does |
|---|---|
| `builder up` | `docker compose up -d` — starts the `sheng-builder` container |
| `builder down` | Stops it |
| `builder status` | `compose ps`, the container's `nix --version`, and the store path count |
| `builder build <attr>` | Builds `#packages.aarch64-linux.<attr>` inside the container and prints its store path |
| `builder fetch <attr> [dir]` | Builds, then streams the result out into `[dir]` (default `./result`) |

> **Notes**
> - `docker` must be on your PATH; the script does not vendor it.
> - The named `nix-store` volume is what keeps a `docker rm` from recompiling the kernel,
>   which is in no binary cache. Do not delete it casually.
> - The flake is bind-mounted read-only at `/workspace`; `SHENG_DOCKER_DIR` overrides the
>   compose directory (default `./docker`).
> - `fetch` uses `tar` rather than `docker cp`, because store paths are read-only and
>   `docker cp` recreates those modes as it copies.

**Without cloning**, if you only want the images:

```sh
mkdir -p result
docker run --rm -v nix-store:/nix -v "$PWD/result:/out" nixos/nix \
  nix --extra-experimental-features 'nix-command flakes' \
      build 'github:SushyDev/nixos-sheng#u-boot' -o /out/uboot
```

### With Nix directly

Only useful on `aarch64-linux`, or with a remote builder that has network access.

```sh
nix build .#u-boot     # $out/boot.img
nix build .#nixos      # $out/sheng-rootfs.sparse.img  (+ sheng-rootfs.img)
nix build .#kernel
```

U-Boot lives in a separate repository, pinned as the non-flake input `u-boot-src`. To
iterate on it without pushing:

```sh
nix build .#u-boot --override-input u-boot-src ../u-boot
```

---

## Flashing

> **Warning**
> This **erases everything on the tablet**, including Android. Dual-boot is not supported.

**Prerequisites:** an unlocked bootloader, and `fastboot` on your PATH.

To enter fastboot: hold **POWER for ~15 s** until the device powers off, then hold
**VOLUME DOWN** and plug the USB cable in.

```sh
fastboot erase dtbo_ab
fastboot flash boot_ab  boot.img
fastboot flash userdata sheng-rootfs.sparse.img
fastboot reboot
```

Both slots are written because ABL chooses which one to boot and the choice is not
yours to make reliably.

The scripted equivalents, which validate the images first and refuse to write anything
but their hardcoded partitions:

```sh
nix run .#fastboot-flash    # boot_a + boot_b from ./result/boot.img
nix run .#flash-rootfs      # userdata from ./result/sheng-rootfs.sparse.img
```

> **Note** — these two do not erase `dtbo`. Do that by hand, once, on a first install.
> `flash-rootfs` asks you to type `wipe` to confirm.

> **If the device boots into fastboot on its own and stays there**, the A/B retry counter
> ran out. Recover with `fastboot set_active b && fastboot reboot`. Once NixOS is up,
> `services.shengBootSlot.enable` (on by default) stops it from happening again.

---

## First boot

> **Important — these are bring-up defaults, not safe ones.**
> The image ships with **root autologin** on tty1 and both serial consoles, a **baked root
> password (`password`)**, and `networking.firewall.enable = false`. Change all three
> before the device is on a network you do not control.

Flashing `userdata` also wipes any Wi-Fi configuration and SSH keys, so a freshly flashed
device is not reachable over the network. The way in is a **USB keyboard** — plug one into
the Type-C port (a hub works) and tty1 autologins to root. From there, join a network and
install your key.

> **Note** — the USB serial gadget console is **off by default**
> (`services.shengSerialConsole.enable`). Binding a gadget driver to the UDC pins the port
> in peripheral mode, which is exactly what stops hubs, keyboards and DisplayPort alt mode
> from working. Turn it on only while debugging — see
> [DEVELOPMENT.md](DEVELOPMENT.md#getting-a-shell-on-the-device).

The first boot registers the Nix store database and replaces the image's single-entry boot
menu with a real generation list; that is a one-shot unit and takes a moment.

---

## Using this repository as a flake input

Replace `SushyDev` with your own fork if you have one.

### Build a system from it

```nix
{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nixos-sheng.url = "github:SushyDev/nixos-sheng";
  };

  outputs = { nixpkgs, nixos-sheng, ... }: {
    nixosConfigurations.sheng = nixos-sheng.lib.shengSystem {
      inherit nixpkgs;
      modules = [ ./hosts/sheng.nix ];
    };
  };
}
```

`shengSystem` builds its own `pkgs` with the sheng overlay and `allowUnfree = true`
(the QTEE and vendor blobs are proprietary), so you do not have to configure either.

The options worth setting in `./hosts/sheng.nix`:

| Option | Default | Meaning |
|---|---|---|
| `sheng.rootfs.partlabel` | `"userdata"` | GPT label to install onto. Shared by the root filesystem, the kernel's `root=` and the image builder. |
| `sheng.rootfs.imageSize` | `"10G"` | Size to grow the image to; `null` auto-sizes to contents. `null` does **not** make flashing faster — the sparse image shrinks by 0.02% — and it leaves only ~160 MB free instead of 7.5 GB should `growfs` fail. Keep the default unless you have a reason. |
| `sheng.rootfs.keepRawImage` | `false` | Also emit the raw ext4 image beside the sparse one. Costs `imageSize` of disk per build for a file nothing reads; turn it on to loopback-mount the filesystem. |
| `sheng.boot.configurationLimit` | `10` | Generations offered in U-Boot's menu. Each costs ~40 MiB of kernel in `/boot`. |
| `sheng.boot.dtbName` | `"qcom/sm8550-xiaomi-sheng.dtb"` | Device tree the menu entries point at. |
| `services.shengFirmware.enable` | `true` | The whole vendor userspace stack. |
| `services.shengBootSlot.enable` | `true` | `qbootctl -m` after boot — leave this on. |
| `services.shengNixBootstrap.enable` | `true` | First-boot store registration and boot-menu regeneration. |
| `services.shengSerialConsole.enable` | `false` | Root console on the USB serial gadget (`ttyGS0`). Costs USB host mode while on — no hubs, keyboards or DP alt mode. Debugging only. |

Also exported: `nixosModules.default` (all modules) and `nixosModules.firmware` (just the
vendor userspace) for composing your own system, and `overlays.default`, which adds
`shengKernel` and `shengPackages` to any nixpkgs.

### Re-export the build and flash commands into your own flake

So `nix build` and `nix run` work from *your* repository, with no clone of this one:

```nix
outputs = { self, nixpkgs, nixos-sheng, ... }:
let
  host = "aarch64-darwin";   # the machine you flash from
in {
  packages.aarch64-linux = {
    boot-img = nixos-sheng.packages.aarch64-linux.u-boot;
    rootfs   = self.nixosConfigurations.sheng.config.system.build.shengImage;
  };

  # find-sheng, exec, flash-uboot, fastboot-flash, flash-rootfs,
  # soak, sheng-mdss-status, read-blackbox, capture-linux-dpu, builder
  apps.${host} = nixos-sheng.apps.${host};
};
```

```sh
nix build .#boot-img .#rootfs
nix run   .#fastboot-flash -- ./result/boot.img
```

The `apps` are exported for all four host systems (`aarch64`/`x86_64` × `darwin`/`linux`),
so the flashing and debugging side needs no aarch64 builder at all — only the two image
packages do.

> **Caveat** — `builder` is the one app that does **not** work purely by flake reference.
> It drives `docker compose` out of a `./docker` directory and bind-mounts `../` as the
> build workspace, neither of which exists without a checkout. Use the
> [no-clone `docker run`](#with-docker-recommended) instead.

---

## Firmware

`services.shengFirmware.enable` installs the lot. Individually, via the overlay's
`shengPackages`:

| Package | What it is |
|---|---|
| `sheng-firmware-blobs` | The Qualcomm/Xiaomi firmware images (ADSP, CDSP, modem, WLAN, touch). Installed via `hardware.firmware` **uncompressed** — this kernel has no `FW_LOADER_COMPRESS`. |
| `fastrpc` | The FastRPC daemon (`adsprpcd-sensorspd`) that carries every DSP-side service. |
| `libssc` | Qualcomm's Sensor Sub-System client library — the sensors sit on top of it. |
| `sheng-sensors` | udev rules binding the SSC sensor nodes. |
| `iio-sensor-proxy` | Accelerometer/ALS to the desktop. **Currently disabled** — see [What is not implemented](#what-is-not-implemented). |
| `sheng-devauth` | Device authentication service, required by the fingerprint stack. |
| `sheng-fingerprint` | FPC1553 reader: `fprintd` integration, `qteesupplicant` and `sfsconfig` for the TrustZone side, and its udev rules. |
| `sheng-thp` | Touch Host Processing — the DSP-side half of the touchscreen. |
| `sheng-pen-status` | Stylus battery/proximity reporting (XDG autostart). |
| `sheng-keyboard-helper` | Xiaomi keyboard cover: mic-mute key (user unit) and lid-angle reporting (system unit). |
| `sheng-mipps-auth` | 120 W charging authentication — without it the charger negotiates down. |
| `sheng-charger-mode` | Offline/charging-mode handling. |
| `alsa-ucm-sheng` | ALSA UCM2 profile (`Xiaomi/sheng`) so audio routing works. |

Each lives in its own directory under `nixos/packages/firmware/`, holding a `default.nix`
plus whatever unit files, udev rules or configs it installs.

---

## Credits

This port stands on other people's work.

- **[map220v](https://github.com/map220v)** — the mainline kernel port, TWRP, and the
  original `sm8550-xiaomi-sheng.dts` that this board's device tree is trimmed down from.
  The only third-party copyright line in the sheng-specific U-Boot code is theirs.
- **[ianchb](https://github.com/ianchb)** — [`sm8550-mainline`](https://github.com/ianchb/sm8550-mainline)
  (branch `sheng-7.2.0`), the kernel this actually runs, and
  [`debian-sheng`](https://github.com/ianchb/debian-sheng), the source of the `sm8550.config`
  kernel configuration and of the vendor firmware/userspace packaging ported here. This
  README is modelled on theirs.
- **[alghiffaryfa19](https://gitlab.postmarketos.org/alghiffaryfa19)** — the postmarketOS
  `pmaports` device port, including the ALSA UCM `HiFi.conf` used here.
- **[sm8550-mainline](https://github.com/sm8550-mainline)** — the upstream device-tree and
  enablement effort for this SoC.
- **[DotRedstone/nixos-sheng](https://github.com/DotRedstone/nixos-sheng)** — an
  independent Mobile-NixOS-based port of the same tablet, and the inspiration for a
  generation picker in the bootloader.
- **Casey Connolly and Linaro** — the upstream U-Boot Qualcomm board support this fork
  builds on.
- **[U-Boot](https://u-boot.org)** and **[NixOS](https://nixos.org)**.

### Licensing

This repository's own Nix expressions, modules and scripts are **MIT** ([LICENSE](../LICENSE)).
That grant does not extend to what the flake fetches or embeds:

| Component | License |
|---|---|
| Kernel (`ianchb/sm8550-mainline`), and the patch hunks in `packages/kernel/default.nix` | `GPL-2.0-only` |
| U-Boot fork ([`SushyDev/u-boot`](https://github.com/SushyDev/u-boot)) | `GPL-2.0-or-later`; the device tree is `GPL-2.0-only OR BSD-3-Clause` |
| `fastrpc`, `sheng-devauth` | `BSD-3-Clause` |
| `sheng-fingerprint`, `sheng-thp`, `sheng-keyboard-helper` | `Apache-2.0` (fingerprint also bundles libfprint, `LGPL-2.1+`) |
| `libssc` | `GPL-3.0-only` |
| `sheng-pen-status` | `GPL-2.0-only` |
| `iio-sensor-proxy` | `GPL-3.0-only` |
| `alsa-ucm-sheng` | `MIT` |
| `sheng-firmware-blobs`, `sheng-sensors`, `sheng-mipps-auth`, `sheng-charger-mode` | **Proprietary** (`unfree`) |

Every derivation carries a `meta.license`, so `allowUnfree` gates the proprietary ones —
which is why `shengSystem` sets it.

> **Warning** — the built rootfs image contains proprietary Xiaomi and Qualcomm firmware
> that carries no redistribution grant. Building it for your own device is one thing;
> **publishing the resulting image is redistribution**, and nothing here licenses you to do
> that. Distribute the flake, not the image.

Sources for the GPL components are pinned by exact revision in `flake.lock`, and the image
bakes the whole flake into `/etc/nixos`, so a device carries the recipe for its own
software.

---

## Further reading

- **[DEVELOPMENT.md](DEVELOPMENT.md)** — the scripts, the three diagnostic side channels,
  how to opt into debug builds, and the hazards worth knowing before you change anything.
