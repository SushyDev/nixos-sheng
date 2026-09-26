# nixos-sheng

NixOS and U-Boot for the **Xiaomi Pad 6S Pro 12.4** (`sheng`, SM8550).

A daily-drivable tablet on mainline Linux. Installing **wipes the device** and needs an
**unlocked bootloader**; no dual-boot.

- **U-Boot** takes over the live boot splash, with a volume-key menu of every NixOS
  generation. [UBOOT.md](UBOOT.md)
- **NixOS modules** configure the hardware only; users, desktop and services are yours.
  [CONFIGURATION.md](CONFIGURATION.md)

## Hardware

| Component | Status | Details |
|---|:---:|---|
| Display | ✅ | 3048×2032 at 144 Hz over dual DSI with DSC, backlight, Adreno 740 acceleration |
| Touch and pen | ✅ | Multitouch, Xiaomi pens with pressure, pen battery and pairing |
| Keyboard cover | ✅ | Authenticated like on Android, backlight, mic-mute LED, turns off when folded back |
| Speakers | ✅ | Six amps with speaker protection; stereo follows rotation, portrait plays mono |
| Audio I/O | ✅ | Stereo microphones, headset jack, DisplayPort audio |
| Sensors | ✅ | Auto-rotate within a second of boot, light, proximity, compass |
| Fingerprint | ✅ | Through TrustZone, for SDDM, sudo and polkit (1Password too) |
| Wi-Fi, Bluetooth | ✅ | With the tablet's factory MAC addresses |
| Battery | ✅ | Charge level, and 120 W fast charging through Xiaomi's charger authentication |
| USB-C | ✅ | Host mode, hubs, keyboards, DisplayPort out up to 120 Hz |
| Suspend | ⚠️ | Deep sleep works; the power button cannot wake it yet |
| Cameras | ⚠️ | Front and main rear work; the second rear needs libcamera support |
| External monitors | ⚠️ | 120 Hz without DSC; a monitor's USB hub works when it prefers data over quality |
| HDR | ❌ | |

## Install

```sh
nix run .#builder -- up && nix run .#builder -- fetch u-boot && nix run .#builder -- fetch nixos
fastboot erase dtbo_ab && fastboot flash boot_ab out/boot.img
fastboot erase userdata && fastboot flash userdata out/sheng-rootfs.sparse.img && fastboot reboot
```

Details, and why `erase userdata` is mandatory: [INSTALL.md](INSTALL.md). Prebuilt
`boot.img`: [Releases](https://github.com/SushyDev/nixos-sheng/releases).

> The reference image logs root in without a password prompt, sets it to `password` and
> opens SSH. Change it before going online.

## Licensing

Nix code is MIT. The image contains Xiaomi/Qualcomm firmware with **no redistribution
grant**: build it yourself, never publish it. Component licenses are in each package's
`meta.license`.

## Credits

[map220v](https://github.com/map220v) (kernel port, device tree) ·
[ianchb](https://github.com/ianchb) (kernel, config, vendor packaging) ·
[alghiffaryfa19](https://gitlab.postmarketos.org/alghiffaryfa19) (postmarketOS port, UCM) ·
[DotRedstone](https://github.com/DotRedstone/nixos-sheng) (generation picker idea, fixes) ·
[sm8550-mainline](https://github.com/sm8550-mainline) · Linaro (U-Boot Qualcomm) · U-Boot · NixOS
