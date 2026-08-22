# Mark the running A/B slot as successful, so the bootloader stops
# counting down towards declaring it dead.
#
# WHY THIS IS NEEDED
#
# sheng uses Android A/B slots, and ABL tracks their state in the GPT
# partition attribute bits of boot_a/boot_b (NOT in the misc partition's
# bootloader_control struct -- that is all zeros on this device). The
# Qualcomm layout is:
#
#     bits 48-49  priority
#     bit  50     active
#     bits 51-53  tries remaining
#     bit  54     successful
#     bit  55     unbootable
#
# ABL decrements "tries remaining" every time it hands off to a slot.
# On Android, userspace calls the boot-control HAL once it is happy,
# which sets bit 54 and stops the countdown. Nothing in a plain Linux
# userspace does that -- note the `bootctl` in PATH is systemd-boot's,
# an unrelated tool -- so the counter only ever falls. At zero, ABL sets
# bit 55 and refuses to load the slot, dropping to fastboot instead.
#
# That is not hypothetical: slot _a reached 0 and was marked unbootable,
# which presents as "the device boots to fastboot and stays there", and
# `fastboot continue` reports "Failed to load image from partition:
# Load Error". Recovery is `fastboot set_active <other slot>`.
#
# qbootctl is the Qualcomm boot-control HAL ported to Linux and writes
# exactly those attribute bits. `-m` with no argument marks the current
# slot, so nothing here hardcodes a slot letter.
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

      Enabled by default, and deliberately not gated behind
      {option}`services.xiaomiSheng.enable`: this is boot
      infrastructure rather than a vendor daemon, and a system with the
      vendor stack turned off still needs its slot marked or it will
      eventually refuse to boot.
    '';
  };

  config = lib.mkIf cfg.enable {
    # Also useful by hand: bare `qbootctl` dumps the state of both slots.
    environment.systemPackages = [ pkgs.qbootctl ];

    systemd.services.sheng-mark-boot-successful = {
      description = "Mark the booted A/B slot successful";

      # multi-user.target, not graphical.target. The failure this
      # prevents is the device becoming unbootable, so the bar for
      # "this boot worked" should be the system reaching a usable
      # multi-user state -- not the GUI coming up. A headless or
      # broken-GUI boot still needs the slot marked.
      after = [ "multi-user.target" ];
      wantedBy = [ "multi-user.target" ];

      # No slots, nothing to mark: don't fail the boot over it.
      unitConfig.ConditionPathExists = [
        "/dev/disk/by-partlabel/boot_a"
        "/dev/disk/by-partlabel/boot_b"
      ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        # Marking an already-marked slot is a no-op, so this is safe to
        # re-run. Left to fail loudly rather than retrying: a failure
        # here means the GPT write did not land, which is worth seeing
        # in `systemctl --failed` rather than silently papering over.
        ExecStart = "${lib.getExe pkgs.qbootctl} -m";
      };
    };
  };
}
