# Audio: UCM search path, UCM-not-ACP, and applying the verb at boot.
#
# Three separate things were wrong; all three are needed.
#
# 1. ALSA_CONFIG_UCM2 (firmware.nix) REPLACES ALSA's UCM search path
#    rather than extending it, so pointing it at a package holding only
#    Xiaomi/sheng/*.conf hid ucm2/lib and ucm2/ucm.conf. Fixed there with
#    a union of the sheng profile and upstream alsa-ucm-conf.
#
# 2. WirePlumber defaults to api.alsa.use-acp = true, PulseAudio's card
#    profile system, which never consults UCM.
#
# 3. Nothing ever applied the HiFi verb. Without it every PCM open fails
#    with EINVAL -- "hw:0,0: playback open failed: Invalid argument" --
#    and wireplumber reports Dummy Output and no sources. Setting the verb
#    by hand and restarting wireplumber immediately produced the real
#    sinks and the MultiMedia3 capture source, which is what this service
#    now does at boot.
#
# The qcom-apm "CMD timeout for [1001021]" in dmesg is a red herring:
# it is logged on every boot, including boots where audio then works.
{ config, lib, pkgs, ... }:

let
  ucm = pkgs.symlinkJoin {
    name = "alsa-ucm2-sheng";
    paths = [ pkgs.shengPackages.alsa-ucm-sheng pkgs.alsa-ucm-conf ];
  };
in
{
  services.pipewire.wireplumber.extraConfig."11-sheng-alsa-ucm" = {
    "monitor.alsa.rules" = [
      {
        matches = [ { "device.name" = "alsa_card.platform-sound"; } ];
        actions.update-props = {
          "api.alsa.use-acp" = false;
          "api.alsa.use-ucm" = true;
        };
      }

      # Every raw PCM node comes up as audio.channels = 64 -- the DSP's
      # maximum, with no channel positions at all -- so nothing is left or
      # right and stereo content plays with no directionality. UCM says
      # what these actually are: Speaker and Mic3 are 2ch (PlaybackChannels
      # 2 / "Top Stereo Microphones"), so pin them to FL/FR.
      #
      # The names and priorities matter as much: without them the default
      # sink lands on pcm 3, which is DisplayPort, so the desktop plays to
      # a disconnected output and the tablet is silent.
      {
        matches = [ { "node.name" = "alsa_output.platform-sound.playback.0.0"; } ];
        actions.update-props = {
          "node.description" = "Speakers";
          "node.nick" = "Speakers";
          "audio.channels" = 2;
          "audio.position" = [ "FL" "FR" ];
          "priority.driver" = 1200;
          "priority.session" = 1200;
        };
      }
      {
        matches = [ { "node.name" = "alsa_output.platform-sound.playback.1.0"; } ];
        actions.update-props = {
          "node.description" = "Headphones";
          "audio.channels" = 2;
          "audio.position" = [ "FL" "FR" ];
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
          "audio.position" = [ "FL" "FR" ];
          "priority.driver" = 1200;
          "priority.session" = 1200;
        };
      }
    ];
  };

  systemd.services.sheng-alsa-ucm = {
    description = "Apply the sheng HiFi UCM verb";
    wantedBy = [ "multi-user.target" ];
    before = [ "multi-user.target" ];
    unitConfig.ConditionPathExists = "/proc/asound/card0";
    environment.ALSA_CONFIG_UCM2 = "${ucm}/share/alsa/ucm2";
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      # The verb alone is NOT enough. Each SectionDevice carries its own
      # EnableSequence, and the Speaker one is what powers up the four
      # CS35L43 amps -- enabling it is what makes them load their DSP
      # firmware (cirrus/{blh,bll,brl,tlh,tll,trl}-cs35l43-dsp1-spk-prot).
      # With only the verb set, PCMs open and play silence.
      ExecStart = "${pkgs.alsa-utils}/bin/alsaucm -c Xiaomi-Pad6SPro set _verb HiFi set _enadev Speaker set _enadev Mic3";
    };
  };
}
