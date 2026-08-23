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
      ExecStart = "${pkgs.alsa-utils}/bin/alsaucm -c Xiaomi-Pad6SPro set _verb HiFi";
    };
  };
}
