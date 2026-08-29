# The single toggle for every sheng vendor userspace daemon. hardware.nix
# stays unconditional; only vendor-specific daemons live behind this.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.shengFirmware;
  sp = pkgs.shengPackages;
in
{
  options.services.shengFirmware.enable = lib.mkEnableOption "Xiaomi sheng vendor userspace stack (sensors, keyboard/pen/fingerprint/charger auth)";

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      sp.fastrpc
      sp.libssc
      sp.iio-sensor-proxy
      sp.sheng-sensors
      sp.sheng-devauth
      sp.sheng-fingerprint
      sp.sheng-thp
      sp.sheng-pen-status
      sp.sheng-keyboard-helper
      sp.sheng-mipps-auth
      sp.sheng-charger-mode
      sp.alsa-ucm-sheng
    ];

    systemd.packages = [
      sp.fastrpc # adsprpcd-sensorspd.service
      sp.iio-sensor-proxy # iio-sensor-proxy.service (+ .d/10-sheng-sensors.conf)
      sp.sheng-devauth # sheng-devauth.service (Requires=qteesupplicant.service)
      sp.sheng-fingerprint # qteesupplicant.service, sfsconfig.service, fprintd.service.d/*
      sp.sheng-thp # xiaomi-sheng-thp.service
      sp.sheng-mipps-auth # xiaomi-mipps-auth.service
      sp.sheng-charger-mode # xiaomi-charger-mode.service
    ];

    # sheng-fingerprint's drop-in expects the distro to provide fprintd.
    services.fprintd.enable = true;

    # The driver's own default is an FHS path, and a missing trusted app
    # surfaces as a misleading "Print was not found".
    systemd.services.fprintd.environment.FPC1553_TA_PATH = "/run/current-system/firmware/fpcsheng.elf";

    systemd.services = {
      "iio-sensor-proxy".wantedBy = [ "multi-user.target" ];
      "sheng-devauth".wantedBy = [ "sysinit.target" ];
      "qteesupplicant".wantedBy = [ "multi-user.target" ];
      "sfsconfig".wantedBy = [ "qteesupplicant.service" ];
      "xiaomi-sheng-thp".wantedBy = [ "multi-user.target" ];
      "xiaomi-mipps-auth".wantedBy = [ "multi-user.target" ];
      "xiaomi-charger-mode".wantedBy = [ "multi-user.target" ];
    };

    systemd.user.services."xiaomi-sheng-keyboard-helper-micmute" = {
      description = "Xiaomi keyboard mic-mute LED sync";
      after = [ "pipewire-pulse.service" ];
      unitConfig.ConditionPathExists = "/sys/class/leds/nanosic::micmute/brightness";
      serviceConfig = {
        Type = "simple";
        ExecStart = "${sp.sheng-keyboard-helper}/libexec/xiaomi-sheng-keyboard-helper --micmute";
      };
    };

    systemd.services."xiaomi-sheng-keyboard-helper-angle" = {
      description = "Xiaomi keyboard fold-angle helper";
      wants = [ "adsprpcd-sensorspd.service" ];
      after = [ "adsprpcd-sensorspd.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${sp.sheng-keyboard-helper}/libexec/xiaomi-sheng-keyboard-helper --angle";
        Restart = "on-failure";
      };
    };

    services.udev.packages = [
      sp.iio-sensor-proxy # 80-iio-sensor-proxy{,-libssc}.rules
      sp.sheng-sensors # 81-sheng-ssc-sensors.rules
      sp.sheng-fingerprint # 99-qcomtee-fpc.rules
      sp.sheng-mipps-auth # 90-xiaomi-mipps-auth.rules
    ];

    services.udev.extraRules = ''
      SUBSYSTEM=="misc", KERNEL=="nanosic_hinge*", ENV{keyboard_attached}=="1", TAG+="systemd", ENV{SYSTEMD_WANTS}+="xiaomi-sheng-keyboard-helper-angle.service"
      SUBSYSTEM=="input", ATTRS{name}=="Xiaomi Keyboard", TAG+="systemd", ENV{SYSTEMD_USER_WANTS}+="xiaomi-sheng-keyboard-helper-micmute.service"
      SUBSYSTEM=="leds", KERNEL=="nanosic::micmute", MODE="0666"
    '';

    environment.etc."xdg/autostart/xiaomi-pen-status.desktop".source =
      "${sp.sheng-pen-status}/etc/xdg/autostart/xiaomi-pen-status.desktop";

    environment.pathsToLink = [ "/share/alsa" ];
    # A union, not the sheng package alone: ALSA_CONFIG_UCM2 replaces the
    # search path rather than extending it, and hiding ucm2/lib makes UCM fail
    # silently -- every PCM present, zero sinks and sources.
    environment.sessionVariables.ALSA_CONFIG_UCM2 = "${
      pkgs.symlinkJoin {
        name = "alsa-ucm2-sheng";
        paths = [
          sp.alsa-ucm-sheng
          pkgs.alsa-ucm-conf
        ];
      }
    }/share/alsa/ucm2";
  };
}
