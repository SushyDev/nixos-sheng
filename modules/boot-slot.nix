# Mark the running A/B slot successful.
#
# ABL keeps slot state in the GPT partition attribute bits of
# boot_a/boot_b, not in misc's bootloader_control:
#
#     48-49 priority   50 active   51-53 tries   54 successful   55 unbootable
#
# ABL decrements tries on every handoff. Android's boot-control HAL sets
# bit 54 to stop the countdown; plain Linux has nothing that does (the
# bootctl in PATH is systemd-boot's, unrelated). At zero tries ABL sets
# bit 55 and refuses the slot, leaving the device sitting in fastboot.
# Recovery is `fastboot set_active <other>`.
#
# qbootctl writes those bits. `-m` marks the current slot, so no slot
# letter is hardcoded.
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
      Mark the booted A/B slot successful once the system is up.

      Not gated behind {option}`services.shengFirmware.enable`: this is
      boot infrastructure, and a system without the vendor stack still
      stops booting if its slot is never marked.
    '';
  };

  config = lib.mkIf cfg.enable {
    # Bare `qbootctl` dumps both slots.
    environment.systemPackages = [ pkgs.qbootctl ];

    systemd.services.sheng-mark-boot-successful = {
      description = "Mark the booted A/B slot successful";

      # multi-user, not graphical: a broken GUI still needs the slot
      # marked or the device stops booting.
      after = [ "multi-user.target" ];
      wantedBy = [ "multi-user.target" ];

      # No slots, nothing to mark.
      unitConfig.ConditionPathExists = [
        "/dev/disk/by-partlabel/boot_a"
        "/dev/disk/by-partlabel/boot_b"
      ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        # Idempotent. Fails loudly: a failure means the GPT write did not
        # land, which belongs in `systemctl --failed`.
        ExecStart = "${lib.getExe pkgs.qbootctl} -m";
      };
    };
  };
}
