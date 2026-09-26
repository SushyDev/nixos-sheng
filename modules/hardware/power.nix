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
      environment.systemPackages = [
        sp.sheng-mipps-auth
        sp.sheng-charger-mode
      ];

      # Without MiPPS the charger negotiates down from 120 W.
      systemd.packages = [
        sp.sheng-mipps-auth
        sp.sheng-charger-mode
      ];

      services.udev.packages = [ sp.sheng-mipps-auth ];

      systemd.services = {
        xiaomi-mipps-auth.wantedBy = [ "multi-user.target" ];
        xiaomi-charger-mode.wantedBy = [ "multi-user.target" ];
      };
    })
  ];
}
