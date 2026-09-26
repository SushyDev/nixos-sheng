# nixos-sheng

NixOS and U-Boot for the **Xiaomi Pad 6S Pro 12.4** (`sheng`, SM8550).

Display, audio, sensors, fingerprint, touch, pen and keyboard cover work. Installing
**wipes the device** and needs an **unlocked bootloader**; no dual-boot.

- **U-Boot** takes over the live boot splash, with a volume-key menu of every NixOS
  generation. [UBOOT.md](UBOOT.md)
- **NixOS modules** configure the hardware only; users, desktop and services are yours.
  [CONFIGURATION.md](CONFIGURATION.md)

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
