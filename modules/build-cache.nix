# Kernel builds take ~20 minutes here and every driver change needs a full
# one, so cache the object files between builds.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cacheDir = "/var/cache/ccache";
in
{
  programs.ccache = {
    enable = true;
    inherit cacheDir;
    packageNames = [ "shengKernel" ];
  };

  nix.settings.extra-sandbox-paths = [ cacheDir ];

  nixpkgs.overlays = [
    (_: prev: {
      ccacheWrapper = prev.ccacheWrapper.override {
        extraConfig = ''
          export CCACHE_COMPRESS=1
          export CCACHE_DIR="${cacheDir}"
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

  # pc was tried as an aarch64 build machine over binfmt and was slower than
  # building here: ~17 min locally against 70+ min emulated. Cross compiling
  # would be the way to use it, see shengKernelCross in overlay.nix.
  nix.distributedBuilds = false;

  nix.settings = {
    fallback = true;
    builders-use-substitutes = true;
    # nixos-rebuild --sudo runs the client as the calling user, and an
    # untrusted client has its builder settings dropped with only a warning.
    trusted-users = [
      "root"
      "sushy"
    ];
  };
}
