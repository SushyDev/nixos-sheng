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
  };

  outputs =
    {
      self,
      nixpkgs,
      u-boot-src,
    }:
    let
      # Building for this on anything else needs a remote builder.
      target = "aarch64-linux";

      hostSystems = [
        "aarch64-darwin"
        "x86_64-darwin"
        "aarch64-linux"
        "x86_64-linux"
      ];

      forHosts = f: nixpkgs.lib.genAttrs hostSystems (s: f nixpkgs.legacyPackages.${s});

      pkgs = import nixpkgs {
        system = target;
        overlays = [ (import ./overlay.nix) ];
        config.allowUnfree = true;
      };

      # Reference image: drivers plus bringup.nix, the host half that makes a
      # flashed board reachable. Downstream configs supply their own.
      sheng = self.lib.shengSystem {
        inherit nixpkgs;
        modules = [ ./modules/bringup.nix ];
      };

      mkScripts =
        hostPkgs:
        let
          mk =
            name: runtimeInputs:
            hostPkgs.writeShellApplication {
              inherit name runtimeInputs;
              text = builtins.readFile (./scripts + "/${name}");
            };
          find-sheng = mk "find-sheng" [
            hostPkgs.openssh
            hostPkgs.netcat
          ];

          mkPython =
            name: runtimeInputs:
            hostPkgs.runCommand name
              {
                nativeBuildInputs = [
                  hostPkgs.python3
                  hostPkgs.makeWrapper
                ];
              }
              ''
                install -Dm755 ${./scripts}/${name} $out/bin/${name}
                patchShebangs $out/bin/${name}
                ${hostPkgs.lib.optionalString (runtimeInputs != [ ]) ''
                  wrapProgram $out/bin/${name} \
                    --prefix PATH : ${hostPkgs.lib.makeBinPath runtimeInputs}
                ''}
              '';

          # Its own derivation, so read-blackbox cannot find it as a sibling.
          exec = mkPython "exec" [ ];
        in
        {
          inherit find-sheng exec;

          read-blackbox = mkPython "read-blackbox" [ exec ];
          capture-linux-dpu = mkPython "capture-linux-dpu" [ exec ];

          soak = mk "soak" [
            hostPkgs.openssh
            hostPkgs.coreutils
            find-sheng
          ];

          sheng-mdss-status = mk "sheng-mdss-status" [
            hostPkgs.openssh
            hostPkgs.coreutils
            find-sheng
          ];

          builder = mk "builder" [
            hostPkgs.openssh
            hostPkgs.coreutils
          ];

          flash-uboot = mk "flash-uboot" [
            hostPkgs.openssh
            hostPkgs.coreutils
            find-sheng
          ];

          flash-rootfs = mk "flash-rootfs" [
            hostPkgs.android-tools
            hostPkgs.coreutils
          ];

          fastboot-flash = mk "fastboot-flash" [
            hostPkgs.android-tools
            hostPkgs.coreutils
            hostPkgs.gnugrep
          ];
        };
    in
    {
      lib = import ./lib { inherit self; };

      nixosModules = {
        default = ./modules;
        firmware = ./modules/firmware.nix;

        # Opt-in host policy, not a driver. NOT secure -- see its header.
        bringup = ./modules/bringup.nix;
      };

      overlays.default = import ./overlay.nix;

      nixosConfigurations.sheng = sheng;

      packages = forHosts (
        hostPkgs:
        mkScripts hostPkgs
        // nixpkgs.lib.optionalAttrs (hostPkgs.stdenv.hostPlatform.system == target) (
          {
            default = sheng.config.system.build.shengImage;

            nixos = sheng.config.system.build.shengImage;

            u-boot = pkgs.callPackage ./packages/u-boot {
              src = u-boot-src;
              version = u-boot-src.shortRev or "dirty";
            };

            kernel = pkgs.shengKernel;
            mdss-test-module = pkgs.callPackage ./packages/kernel/mdss-test-module { };
          }
          // pkgs.shengPackages
        )
      );

      apps = forHosts (
        hostPkgs:
        builtins.mapAttrs (_: script: {
          type = "app";
          program = nixpkgs.lib.getExe script;
        }) (mkScripts hostPkgs)
      );

      formatter = forHosts (hostPkgs: hostPkgs.nixfmt-rfc-style);
    };
}
