{
  imports = [
    ./audio.nix
    ./boot-slot.nix
    ./camera.nix
    ./extlinux.nix
    ./firmware.nix
    ./hardware.nix
    ./image.nix
    ./nix-bootstrap.nix
    ./serial-console.nix
    ./virtual-keyboard.nix
  ];

  services.shengFirmware.enable = true;
}
