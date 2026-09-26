# SDDM fixes for a device with no keyboard and no fixed orientation. Every
# block is gated on the host having enabled the thing it fixes.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.displayManager.sddm;
  gcfg = config.sheng.greeter;

  sddmGreeter = gcfg.enable && cfg.enable;
  kwinGreeter = sddmGreeter && cfg.wayland.enable && cfg.wayland.compositor == "kwin";
  fingerprintGreeter = sddmGreeter && config.services.fprintd.enable;

  outputConfig = "/var/lib/sddm/.config/kwinoutputconfig.json";
in
{
  options.sheng.greeter.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = ''
      Apply the sheng greeter fixes to the display manager the host
      configured. Set false to run a stock greeter.
    '';
  };

  config = lib.mkMerge [
    (lib.mkIf sddmGreeter {
      # mkOverride 90, not mkDefault: plasma6 pins package = kdePackages.sddm
      # at normal priority, so a default here would lose.
      services.displayManager.sddm.package = lib.mkOverride 90 pkgs.shengSddm;
    })

    (lib.mkIf kwinGreeter {
      # nixpkgs sets General.InputMethod = "" but never passes kwin
      # --inputmethod, so the keyboard button asks a compositor with no input
      # method to show one. Appended, so later kwin flags are inherited.
      services.displayManager.sddm.settings.Wayland.CompositorCommand =
        "${cfg.wayland.compositorCommand} "
        + "--inputmethod ${lib.getExe' pkgs.kdePackages.plasma-keyboard "plasma-keyboard"}";

      # KWin only auto-rotates in tablet mode, and nothing here drives
      # SW_TABLET_MODE.
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
            # connector name, the one thing knowable up front.
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
    })

    (lib.mkIf fingerprintGreeter {
      # Fingerprint only: this conversation has no one to ask for a password,
      # so pam_unix here would stall until fprintd times out.
      security.pam.services.sddm-fingerprint = {
        fprintAuth = true;
        unixAuth = false;
        startSession = true;
      };

      # Left in both stacks, a typed password waits out the 30s fprintd
      # timeout before PAM ever looks at it.
      security.pam.services.login.fprintAuth = lib.mkDefault false;

      # User unset: the patch verifies against whoever logged in last, which
      # is the account the greeter preselects anyway.
      services.displayManager.sddm.settings.Fingerprint.Enable = true;
    })
  ];
}
