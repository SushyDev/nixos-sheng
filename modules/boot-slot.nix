# Mark the running A/B slot successful. ABL keeps slot state in the GPT
# attribute bits and decrements a try counter on every handoff; at zero the
# device sits in fastboot. Recovery is `fastboot set_active <other>`.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.shengBootSlot;
in
{
  options.services.shengBootSlot.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Mark the booted A/B slot successful once the system is up.";
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ pkgs.qbootctl ];

    systemd.services.sheng-mark-boot-successful = {
      description = "Mark the booted A/B slot successful";

      after = [ "multi-user.target" ];
      wantedBy = [ "multi-user.target" ];

      unitConfig.ConditionPathExists = [
        "/dev/disk/by-partlabel/boot_a"
        "/dev/disk/by-partlabel/boot_b"
      ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${lib.getExe pkgs.qbootctl} -m";
      };
    };
  };
}
