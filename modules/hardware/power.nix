# Suspend, and charging: MiPPS authentication and the charger-mode screen.
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
  config = lib.mkMerge [
    {
      # When `mem` aborts, systemd falls back to s2idle, which hangs this device hard.
      systemd.sleep.settings.Sleep = {
        SuspendState = lib.mkDefault "mem";
        MemorySleepMode = lib.mkDefault "deep";
      };
    }

    (lib.mkIf config.sheng.vendor.enable {
      # MiPPS is started by its udev rule on charger attach.
      systemd.packages = [
        sp.sheng-mipps-auth
        sp.sheng-charger-mode
      ];
      services.udev.packages = [ sp.sheng-mipps-auth ];

      # Its own [Install] section, which systemd.packages does not apply.
      systemd.services.xiaomi-charger-mode.wantedBy = [ "sysinit.target" ];
    })
  ];
}
