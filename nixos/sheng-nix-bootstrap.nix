# Turn the flashed image into a system that can rebuild itself.
#
# WHY THIS IS NEEDED
#
# make-ext4-fs copies the whole closure of system.build.toplevel into the
# image and writes a /nix-path-registration manifest alongside it -- but
# nothing ever reads that manifest. Until it is loaded, every path in
# /nix/store is "invalid" as far as Nix is concerned, so any build
# re-fetches everything and garbage collection would happily delete the
# running system.
#
# `nixos-rebuild` additionally needs two things a freshly-flashed image
# does not have:
#
#   /etc/NIXOS                        the "this is a NixOS system" tag
#   /nix/var/nix/profiles/system      the profile it switches
#
# Confirmed missing on hardware before this existed: /nix/var/nix/profiles
# held only `default` and `per-user`, and /etc/nixos was empty.
#
# nixpkgs' own sd-image.nix solves this with a `register-nix-paths`
# service; this is the same idea, kept separate because this image is not
# built from sd-image.nix (see ../rootfs/builder.nix).
#
# Installing the bootloader here as well is what gives U-Boot a real
# generation list to show. The image ships a single bootstrap
# extlinux.conf; once the system profile above exists, running the
# installer regenerates it properly, with generation 1 as a real entry.
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

      Enabled by default: without it a flashed image can never rebuild
      itself, which is the entire point of shipping the flake in it.
    '';
  };

  config = lib.mkIf cfg.enable {
    # nixos-rebuild --flake needs both of these, and nothing else in this
    # tree sets them, so on-device rebuilds would otherwise require
    # --extra-experimental-features on every invocation.
    nix.settings.experimental-features = [
      "nix-command"
      "flakes"
    ];

    # KEEPS THE U-BOOT RESCUE PATH ALIVE.
    #
    # sheng.env's `bootrescue` boots /boot/Image with no init=, so the
    # kernel's built-in search has to find /sbin/init. The image builder
    # creates that symlink pointing at the flashed generation, but nothing
    # in NixOS maintains it -- so without this it would stay pinned to
    # that first generation forever and eventually point at a
    # garbage-collected path, turning the rescue path into a panic exactly
    # when it is needed.
    #
    # Replaced via a rename so there is never a window with no /sbin/init.
    #
    # Uses $systemConfig, NOT config.system.build.toplevel: activation
    # scripts are an input to building toplevel, so referring to it here
    # is an infinite recursion. The activation runner exports the path of
    # the generation being activated as $systemConfig, which is also more
    # correct -- it points at whatever is actually being switched to.
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

      # Before nix-daemon so no build can observe the half-registered
      # database, and before anything a user might trigger a rebuild from.
      wantedBy = [ "multi-user.target" ];
      before = [ "nix-daemon.service" ];

      # Self-disarming: the manifest only exists on a freshly flashed
      # image, and the script deletes it. Every later boot skips this.
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

        # Now that a system profile exists, the extlinux generation-list
        # installer has something to enumerate. Failure here must not fail
        # the boot: U-Boot's menu entry 0 falls back to booting
        # /boot/Image directly if extlinux.conf is missing or malformed
        # (see ../../u-boot/board/qualcomm/sheng.env), so a bad write is
        # recoverable rather than fatal.
        ${config.system.build.installBootLoader} /run/current-system || \
          echo "sheng: bootloader install failed; U-Boot fallback still applies" >&2

        rm -f /nix-path-registration
      '';
    };
  };
}
