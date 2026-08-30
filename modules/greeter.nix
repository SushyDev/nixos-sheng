# A greeter for a device with no keyboard and no fixed orientation: an
# on-screen keyboard, and a screen that follows the accelerometer. Inert
# unless a host enables SDDM.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.displayManager.sddm;
  kwinGreeter = cfg.enable && cfg.wayland.enable && cfg.wayland.compositor == "kwin";

  # KWin's own state, written as the sddm user. The rotation policy has no
  # system-wide default to set instead.
  outputConfig = "/var/lib/sddm/.config/kwinoutputconfig.json";
in
{
  config = lib.mkIf kwinGreeter {
    # nixpkgs sets General.InputMethod = "" for the kwin greeter but never
    # passes kwin --inputmethod, so Breeze's keyboard button asks a compositor
    # with no input method to show one. Appended through settings rather than
    # replacing wayland.compositorCommand, so later kwin flags are inherited.
    services.displayManager.sddm.settings.Wayland.CompositorCommand =
      "${cfg.wayland.compositorCommand} "
      + "--inputmethod ${lib.getExe' pkgs.kdePackages.plasma-keyboard "plasma-keyboard"}";

    # KWin only auto-rotates in tablet mode, and nothing on this device drives
    # SW_TABLET_MODE, so the greeter needs the Always policy.
    systemd.services.sddm-greeter-rotation = {
      description = "Auto-rotation policy for the SDDM greeter";
      before = [ "display-manager.service" ];
      wantedBy = [ "display-manager.service" ];
      path = [ pkgs.jq ];

      serviceConfig.Type = "oneshot";

      script = ''
        install -d -o sddm -g sddm -m 0700 "$(dirname ${outputConfig})"

        if [ -e ${outputConfig} ]; then
          jq 'map(if .name == "outputs" then .data |= map(.autoRotation = "Always") else . end)' \
            ${outputConfig} > ${outputConfig}.new
        else
          # KWin has not run as sddm yet. It matches a saved output by its
          # connector name, which is the one thing knowable up front.
          for connector in /sys/class/drm/card*-*/status; do
            [ "$(cat "$connector")" = connected ] || continue
            basename "''${connector%/status}" | cut -d- -f2-
          done | jq -R -s '[{
            name: "outputs",
            data: split("\n") | map(select(. != "") | {
              connectorName: .,
              autoRotation: "Always",
            }),
          }]' > ${outputConfig}.new
        fi

        chown sddm:sddm ${outputConfig}.new
        mv ${outputConfig}.new ${outputConfig}
      '';
    };
  };
}
