# shengSystem: nixosSystem preconfigured for the Xiaomi Pad 6S Pro.
#
#   nix-sheng.lib.shengSystem { modules = [ ./hosts/sheng.nix ]; }
#
# nixpkgs defaults to this flake's own input; to share one across a fleet,
# either use inputs.nixos-sheng.inputs.nixpkgs.follows or pass it here.
{ self }:

{
  shengSystem =
    {
      nixpkgs ? self.inputs.nixpkgs,
      modules ? [ ],
      system ? "aarch64-linux",
      overlays ? [ ],
      specialArgs ? { },
    }:
    nixpkgs.lib.nixosSystem {
      inherit system;

      pkgs = import nixpkgs {
        inherit system;
        overlays = [ (import ../overlay.nix) ] ++ overlays;
        # QTEE and the firmware blobs are proprietary.
        config.allowUnfree = true;
      };

      specialArgs = {
        inherit self;
      }
      // specialArgs;

      modules = [ ../modules ] ++ modules;
    };
}
