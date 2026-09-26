# Touch (processed in userspace), pen status, and the keyboard cover helpers.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  sp = pkgs.shengPackages;
  helper = "${sp.sheng-keyboard-helper}/libexec/xiaomi-sheng-keyboard-helper";
in
{
  config = lib.mkIf config.sheng.vendor.enable {
    environment.systemPackages = [
      sp.sheng-thp
      sp.sheng-pen-status
      sp.sheng-keyboard-helper
    ];

    systemd.packages = [ sp.sheng-thp ];
    systemd.services.xiaomi-sheng-thp.wantedBy = [ "multi-user.target" ];

    environment.etc."xdg/autostart/xiaomi-pen-status.desktop".source =
      "${sp.sheng-pen-status}/etc/xdg/autostart/xiaomi-pen-status.desktop";

    systemd.services.xiaomi-sheng-keyboard-helper-angle = {
      description = "Xiaomi keyboard fold-angle helper";
      wants = [ "adsprpcd-sensorspd.service" ];
      after = [ "adsprpcd-sensorspd.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        ExecStart = "${helper} --angle";
        Restart = "on-failure";
      };
    };

    systemd.user.services.xiaomi-sheng-keyboard-helper-micmute = {
      description = "Xiaomi keyboard mic-mute LED sync";
      after = [ "pipewire-pulse.service" ];
      unitConfig.ConditionPathExists = "/sys/class/leds/nanosic::micmute/brightness";
      serviceConfig.ExecStart = "${helper} --micmute";
    };

    services.udev.extraRules = ''
      SUBSYSTEM=="misc", KERNEL=="nanosic_hinge*", ENV{keyboard_attached}=="1", TAG+="systemd", ENV{SYSTEMD_WANTS}+="xiaomi-sheng-keyboard-helper-angle.service"
      SUBSYSTEM=="input", ATTRS{name}=="Xiaomi Keyboard", TAG+="systemd", ENV{SYSTEMD_USER_WANTS}+="xiaomi-sheng-keyboard-helper-micmute.service"
      SUBSYSTEM=="leds", KERNEL=="nanosic::micmute", MODE="0666"
    '';
  };
}
