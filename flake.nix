{
  description = "NixOS and U-Boot for the Xiaomi Pad 6S Pro 12.4 (sheng, SM8550)";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    # Not a flake; buildUBoot just needs the tree. Override to iterate
    # without pushing: nix build .#u-boot --override-input u-boot-src ../u-boot
    u-boot-src = {
      url = "github:SushyDev/u-boot/xiaomi-sheng";
      flake = false;
    };

    # Bump the tag to move kernels; version and modDirVersion follow the tree.
    # Local tree: builder build nixos --local-kernel
    kernel-src = {
      url = "github:ianchb/sm8550-mainline/7.2.6-mac";
      flake = false;
    };

    # Base config: debian-sheng's repo-root sm8550.config. Move with the kernel.
    kernel-config = {
      url = "github:ianchb/debian-sheng/60753c1fb711f79ff44aa683917c171f28784ca7";
      flake = false;
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      u-boot-src,
      kernel-src,
      kernel-config,
    }:
    let
      # Building for this on anything else needs a remote builder.
      target = "aarch64-linux";

      hostSystems = [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-linux"
      ];

      forHosts = f: nixpkgs.lib.genAttrs hostSystems (s: f nixpkgs.legacyPackages.${s});

      pkgs = import nixpkgs {
        system = target;
        overlays = [ self.overlays.default ];
        config.allowUnfree = true;
      };

      # Reference image: drivers plus bringup.nix, the host half that makes a
      # flashed board reachable. Downstream configs supply their own.
      sheng = self.lib.shengSystem {
        inherit nixpkgs;
        modules = [
          ./modules/bringup.nix
          { sheng.performance.enable = true; }
        ];
      };

      scriptsFor = hostPkgs: import ./scripts { pkgs = hostPkgs; };
    in
    {
      lib = import ./lib { inherit self; };

      nixosModules = {
        default = ./modules;

        # Opt-in host policy, not a driver. NOT secure -- see its header.
        bringup = ./modules/bringup.nix;
      };

      overlays.default = import ./overlay.nix {
        kernelSrc = kernel-src;
        kernelConfig = kernel-config;
      };

      nixosConfigurations.sheng = sheng;

      packages = forHosts (
        hostPkgs:
        (scriptsFor hostPkgs).packages
        // nixpkgs.lib.optionalAttrs (hostPkgs.stdenv.hostPlatform.system == target) (
          {
            default = sheng.config.system.build.shengImage;

            nixos = sheng.config.system.build.shengImage;

            u-boot = pkgs.callPackage ./packages/u-boot {
              inherit ((scriptsFor pkgs).packages) mk-boot-img;
              zig = pkgs.zig_0_16; # same minor as the devenv's `uboot build`
              src = u-boot-src;
              version = u-boot-src.shortRev or "dirty";
            };

            kernel = pkgs.shengKernel;
          }
          # callPackage's override/overrideDerivation are not packages.
          // nixpkgs.lib.filterAttrs (_: nixpkgs.lib.isDerivation) pkgs.shengPackages
        )
      );

      apps = forHosts (
        hostPkgs:
        builtins.mapAttrs (_: script: {
          type = "app";
          program = nixpkgs.lib.getExe script;
        }) (scriptsFor hostPkgs).packages
      );

      formatter = forHosts (hostPkgs: hostPkgs.nixfmt);
    };
}
