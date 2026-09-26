# TrustZone clients: the fingerprint reader and the keyboard cover's authentication.
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
    # Its udev rule starts qteesupplicant once /dev/tee0 appears.
    systemd.packages = [ sp.sheng-fingerprint ];
    services.udev.packages = [ sp.sheng-fingerprint ];

    systemd.services.sheng-devauth = {
      description = "Xiaomi keyboard accessory authentication";
      requires = [ "qteesupplicant.service" ];
      after = [ "qteesupplicant.service" ];
      wantedBy = [ "sysinit.target" ];
      serviceConfig = {
        ExecStart = lib.getExe sp.sheng-devauth;
        Restart = "on-failure";
        RestartSec = 5;
      };
    };

    services.fprintd.enable = true;

    # A missing TA surfaces as a misleading "Print was not found".
    systemd.services.fprintd.environment.FPC1553_TA_PATH = "/run/current-system/firmware/fpcsheng.elf";
  };
}
