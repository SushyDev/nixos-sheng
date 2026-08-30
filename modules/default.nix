{
  imports = [
    ./audio.nix
    ./boot-slot.nix
    ./camera.nix
    ./extlinux.nix
    ./firmware.nix
    ./greeter.nix
    ./hardware.nix
    ./image.nix
    ./nix-bootstrap.nix
    ./serial-console.nix
  ];

  services.shengFirmware.enable = true;
}
