# Entrypoint module list for nixosConfigurations.sheng.
{ ... }:

{
  imports = [
    ./hardware.nix
    ./sheng-boot-slot.nix
    ./sheng-extlinux.nix
    ./sheng-nix-bootstrap.nix
    ./xiaomi-sheng-services.nix
    ../rootfs/builder.nix
  ];

  # Full vendor sensor/keyboard/fingerprint/pen stack -- see
  # xiaomi-sheng-services.nix.
  services.xiaomiSheng.enable = true;
}
