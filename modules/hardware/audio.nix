# Audio is the sheng UCM profile, which PipeWire's ACP reads like any other: it
# applies the HiFi verb, then each device's sequence as its port is used --
# for Speaker, powering up the four CS35L43 amps and loading their DSP. Jacks
# and priorities come from the profile too.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.sheng.audio;
  card = "XiaomiPad6SPro";

  # ALSA_CONFIG_UCM2 replaces the search path, so it has to carry the stock
  # tree as well; without its ucm2/lib, UCM fails silently.
  ucm2 = "${
    pkgs.symlinkJoin {
      name = "alsa-ucm2-sheng";
      paths = [
        pkgs.shengPackages.alsa-ucm-sheng
        pkgs.alsa-ucm-conf
      ];
    }
  }/share/alsa/ucm2";

  # The card registers seconds after multi-user.target.
  soundCard = "sys-devices-platform-sound-sound-card0-controlC0.device";
in
{
  options.sheng.audio.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Put the sheng UCM profile on ALSA's search path, and follow orientation with the speakers.";
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        environment.sessionVariables.ALSA_CONFIG_UCM2 = ucm2;

        # BLE MIDI registration fails on this controller and crashes WirePlumber.
        services.pipewire.wireplumber.extraConfig."sheng-no-bluez-midi"."wireplumber.profiles".main."monitor.bluez-midi" =
          "disabled";
      }

      (lib.mkIf config.sheng.vendor.enable {
        systemd.services.sheng-audio-rotate = {
          description = "Match speaker channels to device orientation";
          bindsTo = [ soundCard ];
          wantedBy = [ soundCard ];
          wants = [ "iio-sensor-proxy.service" ];
          after = [
            soundCard
            "iio-sensor-proxy.service"
          ];
          path = [
            pkgs.alsa-utils
            config.hardware.sensor.iio.package
          ];
          serviceConfig = {
            Restart = "always";
            RestartSec = 5;
          };
          script = ''
            top="TLH TLL TRL"
            bottom="BLH BLL BRL"
            # One amixer for the whole batch: a write per process piles up behind
            # the control events the writes themselves raise.
            set_amps() {
              for amp in $1; do
                echo "cset name='$amp $2' $3"
              done
            }

            # In landscape the top amps are one channel and the bottom amps the
            # other, so flipping which takes slot 0 swaps the pair in the amps
            # themselves. In portrait that pair would be above and below you:
            # each amp's DSP gets both channels on its second input instead, and
            # the firmware's input conditioner mixes them: the mono mix takes both
            # below its crossover, the balance splits what is above it evenly.
            # Only writes that change a value raise a control event.
            apply() {
              case "$1" in
                normal | bottom-up)
                  [ "$1" = normal ] && left=$top right=$bottom || left=$bottom right=$top
                  set_amps "$top $bottom" "DSP1 Protection 5f20e INP_CND_MM_XO_EN" 0x00,0x00,0x00,0x00
                  set_amps "$top $bottom" "DSP1 Protection 5f20e INP_CND_CH_BAL" 0x00,0x00,0x00,0x00
                  set_amps "$top $bottom" "DSP RX2 Source" ASPRX1
                  set_amps "$left" "ASPRX1 Slot Position" 0
                  set_amps "$right" "ASPRX1 Slot Position" 1
                  ;;
                left-up | right-up)
                  set_amps "$top $bottom" "ASPRX1 Slot Position" 0
                  set_amps "$top $bottom" "ASPRX2 Slot Position" 1
                  set_amps "$top $bottom" "DSP RX2 Source" ASPRX2
                  set_amps "$top $bottom" "DSP1 Protection 5f20e INP_CND_CH_BAL" 0x00,0x40,0x00,0x00
                  set_amps "$top $bottom" "DSP1 Protection 5f20e INP_CND_MM_XO_EN" 0x00,0x00,0x00,0x01
                  ;;
              esac | amixer -c ${card} -q -s
            }

            # monitor-sensor holds the claim that makes readings flow, and
            # re-claims whenever the proxy restarts. The HiFi verb sets up the
            # amps for upright and whoever opens the card applies it, so put
            # them back when it does.
            {
              monitor-sensor --accel &
              alsactl monitor hw:${card} &
              wait
            } | while read -r line; do
              # Take everything already queued, then apply once.
              stale=
              while :; do
                case "$line" in
                  "=== Has accelerometer (orientation: "*)
                    orientation=''${line#*orientation: }
                    orientation=''${orientation%%,*}
                    stale=1
                    ;;
                  *"Accelerometer orientation changed: "*)
                    orientation=''${line##*: }
                    stale=1
                    ;;
                  *"Slot Position"* | *"DSP RX2 Source"* | *INP_CND_MM_XO_EN* | *INP_CND_CH_BAL,*) stale=1 ;;
                esac
                read -r -t 0.2 line || break
              done
              [ -z "$stale" ] || apply "$orientation"
            done
          '';
        };
      })
    ]
  );
}
