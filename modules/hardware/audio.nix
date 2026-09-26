# Audio needs the UCM search path, WirePlumber using UCM rather than ACP, and
# the HiFi verb applied at boot -- without which every PCM open fails with EINVAL.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.sheng.audio;
  wireplumber = config.services.pipewire.enable && config.services.pipewire.wireplumber.enable;

  # The card registers seconds after multi-user.target, so the verb has to hang
  # off the card's own device unit or WirePlumber races it and gives up.
  soundCard = "sys-devices-platform-sound-sound-card0-controlC0.device";

  # A union: ALSA_CONFIG_UCM2 replaces the search path, and without ucm2/lib UCM fails silently.
  ucm2 = "${
    pkgs.symlinkJoin {
      name = "alsa-ucm2-sheng";
      paths = [
        pkgs.shengPackages.alsa-ucm-sheng
        pkgs.alsa-ucm-conf
      ];
    }
  }/share/alsa/ucm2";

  node = name: props: {
    matches = [ { "node.name" = name; } ];
    actions.update-props = props;
  };
  stereo = {
    "audio.channels" = 2;
    "audio.position" = [
      "FL"
      "FR"
    ];
  };
  priority = p: {
    "priority.driver" = p;
    "priority.session" = p;
  };
in
{
  options.sheng.audio.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Apply the HiFi UCM verb at boot and drive this card through UCM in WirePlumber.";
  };

  config = lib.mkMerge [
    (lib.mkIf (cfg.enable && wireplumber) {
      services.pipewire.wireplumber.extraConfig."11-sheng-alsa-ucm" = {
        "monitor.alsa.rules" = [
          {
            matches = [ { "device.name" = "alsa_card.platform-sound"; } ];
            actions.update-props = {
              "api.alsa.use-acp" = false;
              "api.alsa.use-ucm" = true;
            };
          }

          # Raw PCM nodes come up as 64 channels with no positions, and without
          # priorities the default sink lands on DisplayPort.
          (node "alsa_output.platform-sound.playback.0.0" (
            {
              "node.description" = "Speakers";
              "node.nick" = "Speakers";
            }
            // stereo
            // priority 1200
          ))
          (node "alsa_output.platform-sound.playback.1.0" (
            { "node.description" = "Headphones"; } // stereo // priority 1100
          ))
          (node "alsa_output.platform-sound.playback.3.0" (
            { "node.description" = "DisplayPort"; } // priority 100
          ))
          (node "alsa_input.platform-sound.capture.2.0" (
            { "node.description" = "Built-in Microphones"; } // stereo // priority 1200
          ))
        ];
      };

      # BLE MIDI registration fails on this controller and crashes WirePlumber.
      services.pipewire.wireplumber.extraConfig."12-sheng-no-bluez-midi"."wireplumber.profiles".main."monitor.bluez-midi" =
        "disabled";
    })

    (lib.mkIf cfg.enable {
      environment.systemPackages = [ pkgs.shengPackages.alsa-ucm-sheng ];
      environment.pathsToLink = [ "/share/alsa" ];
      environment.sessionVariables.ALSA_CONFIG_UCM2 = ucm2;

      systemd.services.sheng-alsa-ucm = {
        description = "Apply the sheng HiFi UCM verb";
        bindsTo = [ soundCard ];
        after = [ soundCard ];
        wantedBy = [ soundCard ];
        environment.ALSA_CONFIG_UCM2 = ucm2;
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          # The verb alone plays silence: the Speaker device's EnableSequence
          # powers up the four CS35L43 amps and loads their DSP firmware.
          ExecStart = "${pkgs.alsa-utils}/bin/alsaucm -c Xiaomi-Pad6SPro set _verb HiFi set _enadev Speaker set _enadev Mic3";
        };
      };

      systemd.services.display-manager.after = [ "sheng-alsa-ucm.service" ];
    })

    (lib.mkIf (cfg.enable && config.sheng.vendor.enable) {
      systemd.services.sheng-audio-rotate = {
        description = "Match speaker channels to device orientation";
        partOf = [ "sheng-alsa-ucm.service" ];
        wantedBy = [ "sheng-alsa-ucm.service" ];
        wants = [ "iio-sensor-proxy.service" ];
        after = [
          "sheng-alsa-ucm.service"
          "iio-sensor-proxy.service"
        ];
        path = [
          pkgs.alsa-utils
          pkgs.glib.bin
          pkgs.systemd
        ];
        serviceConfig = {
          Restart = "always";
          RestartSec = 5;
        };
        script = ''
          orientation() {
            busctl get-property net.hadess.SensorProxy /net/hadess/SensorProxy \
              net.hadess.SensorProxy AccelerometerOrientation | cut -d'"' -f2
          }

          # HiFi.conf wires the top amps to slot 0 and the bottom amps to slot 1;
          # flipping the slots swaps the stereo pair in the amps themselves.
          apply() {
            case "$1" in
              normal) top=0 bottom=1 ;;
              bottom-up) top=1 bottom=0 ;;
              *) return 0 ;;
            esac
            for amp in TLH TLL TRL; do
              amixer -c0 cset name="$amp ASPRX1 Slot Position" "$top" >/dev/null
            done
            for amp in BLH BLL BRL; do
              amixer -c0 cset name="$amp ASPRX1 Slot Position" "$bottom" >/dev/null
            done
          }

          busctl call net.hadess.SensorProxy /net/hadess/SensorProxy \
            net.hadess.SensorProxy ClaimAccelerometer >/dev/null
          apply "$(orientation)"

          gdbus monitor --system --dest net.hadess.SensorProxy \
              --object-path /net/hadess/SensorProxy |
            while read -r event; do
              case "$event" in
                *AccelerometerOrientation*) apply "$(orientation)" ;;
              esac
            done
        '';
      };
    })
  ];
}
