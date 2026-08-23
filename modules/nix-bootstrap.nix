# Make a flashed image able to rebuild itself.
#
# make-ext4-fs copies the toplevel closure into the image and writes
# /nix-path-registration, but nothing reads it. Until it is loaded every
# store path is invalid to Nix, so builds refetch everything and GC would
# delete the running system. nixos-rebuild also needs /etc/NIXOS and
# /nix/var/nix/profiles/system, neither of which a fresh image has.
#
# Same idea as nixpkgs' sd-image.nix register-nix-paths; separate because
# this image is not built from sd-image.nix.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.shengNixBootstrap;
  nix = config.nix.package.out;
in
{
  options.services.shengNixBootstrap.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = ''
      Register the baked-in store paths and create the system profile on
      first boot, so {command}`nixos-rebuild` works on the device.
    '';
  };

  config = lib.mkIf cfg.enable {
    # Otherwise every on-device rebuild needs
    # --extra-experimental-features.
    nix.settings.experimental-features = [
      "nix-command"
      "flakes"
    ];

    # Keeps U-Boot's rescue path alive: bootrescue boots /boot/Image with
    # no init=, so the kernel's built-in search must find /sbin/init.
    # Nothing else maintains this symlink, so it would stay pinned to the
    # flashed generation and eventually point at a GC'd path.
    #
    # $systemConfig, not config.system.build.toplevel: activation scripts
    # are an input to building toplevel, so that is infinite recursion.
    #
    # Renamed into place, so there is never a window with no /sbin/init.
    system.activationScripts.shengSbinInit = {
      text = ''
        mkdir -p /sbin
        ln -sfn "$systemConfig/init" /sbin/.init.tmp
        mv -T /sbin/.init.tmp /sbin/init
      '';
      deps = [ ];
    };

    systemd.services.sheng-register-nix-paths = {
      description = "Register baked-in Nix store paths and system profile";

      # Before nix-daemon, so no build sees a half-registered database.
      wantedBy = [ "multi-user.target" ];
      before = [ "nix-daemon.service" ];

      # The manifest exists only on a fresh image, and the script deletes
      # it. Later boots skip this.
      unitConfig.ConditionPathExists = "/nix-path-registration";

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };

      script = ''
        set -eu

        ${lib.getExe' nix "nix-store"} --load-db < /nix-path-registration

        touch /etc/NIXOS
        ${lib.getExe' nix "nix-env"} \
          -p /nix/var/nix/profiles/system --set /run/current-system

        # The generation list needs the profile that now exists. A failed
        # write is not fatal: U-Boot falls back to booting /boot/Image.
        ${config.system.build.installBootLoader} /run/current-system || \
          echo "sheng: bootloader install failed; U-Boot fallback applies" >&2

        rm -f /nix-path-registration
      '';
    };
  };
}
