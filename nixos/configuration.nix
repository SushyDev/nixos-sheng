# Entrypoint module list for nixosConfigurations.sheng.
{ ... }:

{
  imports = [
    ./hardware.nix
    ./xiaomi-sheng-services.nix
    ../rootfs/builder.nix
  ];

  # Full vendor sensor/keyboard/fingerprint/pen stack -- see
  # xiaomi-sheng-services.nix.
  services.xiaomiSheng.enable = true;
}
