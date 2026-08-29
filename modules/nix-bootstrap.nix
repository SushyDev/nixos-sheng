# Make a flashed image able to rebuild itself. Nothing reads the
# /nix-path-registration make-ext4-fs writes, so until it is loaded every
# store path is invalid to Nix: builds refetch everything and GC would delete
# the running system.
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
    nix.settings.experimental-features = [
      "nix-command"
      "flakes"
    ];

    # U-Boot's rescue path boots /boot/Image with no init=, so the kernel's
    # built-in search must find /sbin/init. $systemConfig, not
    # config.system.build.toplevel, which recurses.
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

      wantedBy = [ "multi-user.target" ];
      before = [ "nix-daemon.service" ];

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

        ${config.system.build.installBootLoader} /run/current-system || \
          echo "sheng: bootloader install failed; U-Boot fallback applies" >&2

        rm -f /nix-path-registration
      '';
    };
  };
}
