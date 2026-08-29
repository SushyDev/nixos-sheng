# Mark the running A/B slot successful. ABL keeps slot state in the GPT
# attribute bits of boot_a/boot_b, not in misc, and decrements the try counter
# on every handoff; at zero it refuses the slot and the device sits in
# fastboot. Nothing in plain Linux sets the successful bit -- the bootctl in
# PATH is systemd-boot's. Recovery is `fastboot set_active <other>`.
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
    description = ''
      Mark the booted A/B slot successful once the system is up. Not gated
      behind {option}`services.shengFirmware.enable`: a system without the
      vendor stack still stops booting if its slot is never marked.
    '';
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
