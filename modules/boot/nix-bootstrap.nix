# Make a flashed image able to rebuild itself. Nothing reads the
# /nix-path-registration make-ext4-fs writes, so until it is loaded every store
# path is invalid to Nix.
{
  config,
  lib,
  ...
}:

let
  cfg = config.sheng.boot;
  nix = config.nix.package.out;
in
{
  options.sheng.boot.registerStore = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Register the baked-in store paths and create the system profile on first boot.";
  };

  config = lib.mkIf cfg.registerStore {
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
