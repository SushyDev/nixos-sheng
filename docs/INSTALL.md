# Install

## Build

Outputs are `aarch64-linux` only. Use Docker (any host) or Nix with a networked aarch64
builder. Determinate's builder VM has no network, and this kernel is in no cache.

```sh
nix run .#builder -- up             # start the build container
nix run .#builder -- fetch u-boot   # out/boot.img
nix run .#builder -- fetch nixos    # out/sheng-rootfs.sparse.img
```

`builder` also has `down`, `status`, `build <attr>`, `shell` and `run <cmd>`. Keep the
`docker_nix-store` volume: it holds the kernel build.

With Nix directly: `nix build .#u-boot`, `.#nixos`, `.#kernel`. A local U-Boot tree:
`--override-input u-boot-src ../u-boot`.

## Flash

Fastboot: hold POWER ~15 s, then VOLUME DOWN while plugging in USB.

```sh
fastboot erase dtbo_ab
fastboot flash boot_ab boot.img
fastboot erase userdata
fastboot flash userdata sheng-rootfs.sparse.img
fastboot reboot
```

**Always erase `userdata`.** Fastboot leaves the image's empty regions holding old data;
ext4 then fails its checksums and `/` can never grow.

`nix run .#fastboot-flash` and `.#flash-rootfs` do the same with checks.

Stuck in fastboot? `fastboot set_active b && fastboot reboot`.

## First boot

The network is not set up yet: plug a USB keyboard into the Type-C port for a root shell
on tty1. The reference image's root password is `password`; change it.
