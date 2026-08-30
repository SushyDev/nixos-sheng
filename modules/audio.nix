# Audio needs the UCM search path (firmware.nix), WirePlumber using UCM rather
# than ACP, and the HiFi verb applied at boot -- without which every PCM open
# fails with EINVAL.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.sheng.audio;
  wireplumber = config.services.pipewire.enable && config.services.pipewire.wireplumber.enable;

  ucm = pkgs.symlinkJoin {
    name = "alsa-ucm2-sheng";
    paths = [
      pkgs.shengPackages.alsa-ucm-sheng
      pkgs.alsa-ucm-conf
    ];
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
          {
            matches = [ { "node.name" = "alsa_output.platform-sound.playback.0.0"; } ];
            actions.update-props = {
              "node.description" = "Speakers";
              "node.nick" = "Speakers";
              "audio.channels" = 2;
              "audio.position" = [
                "FL"
                "FR"
              ];
              "priority.driver" = 1200;
              "priority.session" = 1200;
            };
          }
          {
            matches = [ { "node.name" = "alsa_output.platform-sound.playback.1.0"; } ];
            actions.update-props = {
              "node.description" = "Headphones";
              "audio.channels" = 2;
              "audio.position" = [
                "FL"
                "FR"
              ];
              "priority.driver" = 1100;
              "priority.session" = 1100;
            };
          }
          {
            matches = [ { "node.name" = "alsa_output.platform-sound.playback.3.0"; } ];
            actions.update-props = {
              "node.description" = "DisplayPort";
              "priority.driver" = 100;
              "priority.session" = 100;
            };
          }
          {
            matches = [ { "node.name" = "alsa_input.platform-sound.capture.2.0"; } ];
            actions.update-props = {
              "node.description" = "Built-in Microphones";
              "audio.channels" = 2;
              "audio.position" = [
                "FL"
                "FR"
              ];
              "priority.driver" = 1200;
              "priority.session" = 1200;
            };
          }
        ];
      };
    })

    (lib.mkIf cfg.enable {
      systemd.services.sheng-alsa-ucm = {
        description = "Apply the sheng HiFi UCM verb";
        wantedBy = [ "multi-user.target" ];
        before = [ "multi-user.target" ];
        unitConfig.ConditionPathExists = "/proc/asound/card0";
        environment.ALSA_CONFIG_UCM2 = "${ucm}/share/alsa/ucm2";
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          # The verb alone plays silence: the Speaker device's EnableSequence
          # powers up the four CS35L43 amps and loads their DSP firmware.
          ExecStart = "${pkgs.alsa-utils}/bin/alsaucm -c Xiaomi-Pad6SPro set _verb HiFi set _enadev Speaker set _enadev Mic3";
        };
      };
    })
  ];
}
