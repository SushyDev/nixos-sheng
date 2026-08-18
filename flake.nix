{
  description = "NixOS for the Xiaomi Pad 6S Pro 12.4 (\"sheng\", SM8550P)";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      system = "aarch64-linux";
      pkgs = import nixpkgs {
        inherit system;
        overlays = [ (import ./overlay.nix) ];
        config.allowUnfree = true; # QTEE/firmware blobs are proprietary
      };
    in
    {
      nixosConfigurations.sheng = nixpkgs.lib.nixosSystem {
        inherit system pkgs;
        specialArgs = { inherit self; };
        modules = [
          ./nixos/configuration.nix
        ];
      };

      packages.${system} = {
        shengImage = self.nixosConfigurations.sheng.config.system.build.shengImage;
        default = self.packages.${system}.shengImage;
        shengKernel = pkgs.shengKernel;
      } // pkgs.shengPackages;

      apps.${system}.build-image = {
        type = "app";
        program = toString (pkgs.writeShellScript "build-sheng-image" ''
          set -euo pipefail
          echo "Building sheng-rootfs.img (this builds the full NixOS closure + kernel, may take a while)..."
          out=$(${pkgs.nix}/bin/nix build --no-link --print-out-paths .#shengImage)
          raw=$(find "$out" -name '*.img' ! -name '*.sparse.img' | head -n1)
          sparse=$(find "$out" -name '*.sparse.img' | head -n1)
          echo ""
          echo "Raw image:    $raw"
          echo "Sparse image: $sparse"
          echo ""
          echo "Flash the sparse image with fastboot (recommended -- fastboot expects sparse):"
          echo "  fastboot flash <partlabel> \"$sparse\""
          echo "Or the raw image with any other flashing tool (dd, etc):"
          echo "  fastboot flash <partlabel> \"$raw\""
          echo ""
          echo "<partlabel> defaults to \"userdata\" (see config.sheng.rootfs.partlabel)."
        '');
      };
    };
}
