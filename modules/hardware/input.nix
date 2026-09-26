# Touch (processed in userspace), pen status, and the keyboard cover helpers.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  sp = pkgs.shengPackages;
in
{
  config = lib.mkIf config.sheng.vendor.enable {
    # The tray app autostarts from its own /etc/xdg/autostart entry.
    environment.systemPackages = [ sp.sheng-pen-status ];

    # The keyboard helper's udev rules start its units when the cover attaches.
    systemd.packages = [
      sp.sheng-thp
      sp.sheng-keyboard-helper
    ];
    services.udev.packages = [ sp.sheng-keyboard-helper ];

    systemd.services.xiaomi-sheng-thp.wantedBy = [ "multi-user.target" ];
  };
}
