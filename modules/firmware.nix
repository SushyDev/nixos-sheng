# The single toggle for every sheng vendor userspace daemon: Qualcomm SSC
# sensors (fastrpc/libssc/iio-sensor-proxy/sheng-sensors), keyboard auth,
# fingerprint (+ its qteesupplicant QTEE runtime), stylus/pen status,
# NT36532E touch host processor, keyboard fold-angle + mic-mute helper,
# MiPPS charger auth, charger-mode UI, and the WCD938X ALSA UCM profile.
#
# hardware.nix (kernel, boot, console, USB gadget serial, base packages)
# stays unconditional -- only vendor-specific daemons live behind this.
{ config, lib, pkgs, ... }:

let
  cfg = config.services.shengFirmware;
  sp = pkgs.shengPackages;
in
{
  options.services.shengFirmware.enable =
    lib.mkEnableOption "Xiaomi sheng vendor userspace stack (sensors, keyboard/pen/fingerprint/charger auth)";

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

    # The sheng-fingerprint package ships a patched libfprint plus the
    # FPC1553 QTEE backend and an fprintd.service.d drop-in that points
    # fprintd's LD_LIBRARY_PATH at them -- but it expects the distro to
    # provide fprintd itself. Without this the drop-in has nothing to
    # attach to: no fprintd, no D-Bus service, and so no fingerprint
    # option anywhere in the desktop, even though the kernel side is up
    # ("fpc1553 fingerprint_fpc: fpc1553 platform side ready") and
    # qteesupplicant/sfsconfig are running.
    services.fprintd.enable = true;

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
    # A UNION of the sheng profile and upstream alsa-ucm-conf, not the
    # sheng package alone. ALSA_CONFIG_UCM2 replaces the search path
    # rather than extending it, so pointing it at a package holding only
    # Xiaomi/sheng/*.conf hides ucm2/lib, ucm2/ucm.conf and everything
    # else UCM needs to initialise. UCM then fails silently: the card is
    # present with all its PCMs (pcm0p pcm1p pcm2c pcm3p) and wireplumber
    # still reports zero sinks and zero sources -- no speakers, no mic.
    environment.sessionVariables.ALSA_CONFIG_UCM2 =
      "${pkgs.symlinkJoin {
        name = "alsa-ucm2-sheng";
        paths = [ sp.alsa-ucm-sheng pkgs.alsa-ucm-conf ];
      }}/share/alsa/ucm2";
  };
}
