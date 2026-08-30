# Drivers only. Host policy (users, greeters, daemons) belongs downstream;
# ./bringup.nix has the minimum for a freshly flashed board and is not
# imported here.
{
  imports = [
    ./audio.nix
    ./boot-slot.nix
    ./build-cache.nix
    ./camera.nix
    ./extlinux.nix
    ./firmware.nix
    ./greeter.nix
    ./hardware.nix
    ./image.nix
    ./nix-bootstrap.nix
    ./power.nix
    ./serial-console.nix
  ];

  services.shengFirmware.enable = true;
}
