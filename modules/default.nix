# Drivers only. Host policy (users, greeters, daemons) belongs downstream;
# ./bringup.nix has the minimum for a freshly flashed board and is not
# imported here.
{ lib, ... }:

{
  imports = [
    ./hardware
    ./boot/extlinux.nix
    ./boot/image.nix
    ./boot/nix-bootstrap.nix
    ./boot/slot.nix
    ./system/build-cache.nix
    ./system/greeter.nix
    ./system/performance.nix
    ./system/serial-console.nix

    (lib.mkRenamedOptionModule [ "services" "shengFirmware" "enable" ] [ "sheng" "vendor" "enable" ])
    (lib.mkRenamedOptionModule
      [ "services" "shengBootSlot" "enable" ]
      [ "sheng" "boot" "markSuccessful" ]
    )
    (lib.mkRenamedOptionModule
      [ "services" "shengNixBootstrap" "enable" ]
      [ "sheng" "boot" "registerStore" ]
    )
    (lib.mkRenamedOptionModule
      [ "services" "shengSerialConsole" "enable" ]
      [ "sheng" "serialConsole" "enable" ]
    )
  ];
}
