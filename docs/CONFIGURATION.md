# Configuration

```nix
nixosConfigurations.sheng = nixos-sheng.lib.shengSystem {
  inherit nixpkgs;
  modules = [ ./hosts/sheng.nix ];
};
```

`nixosModules.default` sets the kernel, device tree, bootloader, firmware and vendor
userspace, and nothing else: no user, login or network. `nixosModules.bringup` adds
the insecure reference login (root autologin, password `password`, SSH).

| Option | Default | |
|---|---|---|
| `sheng.vendor.enable` | on | Sensors, fingerprint, touch, pen, keyboard, 120 W charging |
| `sheng.audio.enable` | on | Speakers, following orientation |
| `sheng.camera.enable` | on | Cameras through libcamera |
| `sheng.greeter.enable` | on | SDDM fixes, if SDDM is enabled |
| `sheng.factoryAddresses.enable` | on | Factory Wi-Fi/Bluetooth MACs |
| `sheng.boot.markSuccessful` | on | Keeps ABL from falling back to fastboot |
| `sheng.boot.configurationLimit` | 10 | Generations in the boot menu |
| `sheng.rootfs.partlabel` | `userdata` | Partition to install to |
| `sheng.rootfs.etcNixosSource` | none | Flake baked into `/etc/nixos` |
| `sheng.performance.enable` | off | zram and OOM tuning for 8 GB |
| `sheng.camera.qtGstreamerBackend` | off | Camera in Qt apps |
| `sheng.buildCache.enable` | off | ccache for on-device kernel builds |
| `sheng.serialConsole.enable` | off | USB serial console; disables USB host |

Packages are in the overlay as `shengPackages`. To build from your own flake, re-export
`nixos-sheng.packages.aarch64-linux.u-boot` and your system's
`config.system.build.shengImage`; flashing apps are in `nixos-sheng.apps`.
