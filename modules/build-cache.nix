# Kernel builds take ~20 minutes on the device and every driver change needs a
# full one, so optionally cache the object files between builds.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.sheng.buildCache;
in
{
  options.sheng.buildCache = {
    enable = lib.mkEnableOption "ccache for shengKernel builds on the device" // {
      description = ''
        Build shengKernel through ccacheStdenv and keep the object cache in
        {option}`sheng.buildCache.directory`. Off by default: it only pays off
        if you rebuild the kernel on the device, and it costs up to 10G there.

        The client running {command}`nixos-rebuild` must be a trusted user, or
        Nix drops the sandbox path with only a warning and every build misses.
      '';
    };

    directory = lib.mkOption {
      type = lib.types.path;
      default = "/var/cache/ccache";
      description = "Where the object cache lives.";
    };
  };

  config = lib.mkIf cfg.enable {
    programs.ccache = {
      enable = true;
      cacheDir = cfg.directory;
      packageNames = [ "shengKernel" ];
    };

    nix.settings.extra-sandbox-paths = [ cfg.directory ];

    # Replaces the wrapper config programs.ccache writes: NOHASHDIR/BASEDIR so
    # a moved $TMPDIR still hits, and a size cap.
    nixpkgs.overlays = [
      (_: prev: {
        ccacheWrapper = prev.ccacheWrapper.override {
          extraConfig = ''
            export CCACHE_COMPRESS=1
            export CCACHE_DIR="${cfg.directory}"
            export CCACHE_UMASK=007
            export CCACHE_BASEDIR="$NIX_BUILD_TOP"
            export CCACHE_NOHASHDIR=1
            export CCACHE_MAXSIZE=10G
            if [ ! -d "$CCACHE_DIR" ]; then
              echo "no CCACHE_DIR ($CCACHE_DIR), is it in extra-sandbox-paths?" >&2
              exit 1
            fi
          '';
        };
      })
    ];

    environment.systemPackages = [ pkgs.ccache ];
  };
}
