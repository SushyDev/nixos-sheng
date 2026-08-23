# Everything a sheng needs to boot and rebuild itself.
{
  imports = [
    ./boot-slot.nix
    ./extlinux.nix
    ./firmware.nix
    ./hardware.nix
    ./image.nix
    ./nix-bootstrap.nix
    ./serial-console.nix
  ];

  services.shengFirmware.enable = true;
}
