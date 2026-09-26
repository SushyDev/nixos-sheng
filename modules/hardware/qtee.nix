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
    environment.systemPackages = [
      sp.sheng-fingerprint
      sp.sheng-devauth
    ];

    systemd.packages = [
      sp.sheng-fingerprint
      sp.sheng-devauth
    ];

    services.udev.packages = [ sp.sheng-fingerprint ];

    systemd.services = {
      qteesupplicant.wantedBy = [ "multi-user.target" ];
      sfsconfig.wantedBy = [ "qteesupplicant.service" ];
      sheng-devauth.wantedBy = [ "sysinit.target" ];
    };

    services.fprintd.enable = true;

    # A missing TA surfaces as a misleading "Print was not found".
    systemd.services.fprintd.environment.FPC1553_TA_PATH = "/run/current-system/firmware/fpcsheng.elf";
  };
}
