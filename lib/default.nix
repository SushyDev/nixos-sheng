# shengSystem: a nixosSystem preconfigured for the Xiaomi Pad 6S Pro.
#
#   nix-sheng.lib.shengSystem {
#     inherit (inputs) nixpkgs;
#     modules = [ ./hosts/sheng.nix ];
#   }
#
# nixpkgs comes from the caller so a fleet shares one nixpkgs. The device
# needs a kernel and firmware that track it; a nixpkgs bump can break them.
{ self }:

{
  shengSystem =
    {
      nixpkgs,
      modules ? [ ],
      system ? "aarch64-linux",
      # Merged into the pkgs this system is built from.
      overlays ? [ ],
      specialArgs ? { },
    }:
    nixpkgs.lib.nixosSystem {
      inherit system;

      # Built here rather than via nixpkgs.overlays so the same pkgs is
      # reachable from lib and packages outputs.
      pkgs = import nixpkgs {
        inherit system;
        overlays = [ (import ../overlay.nix) ] ++ overlays;
        # QTEE and the firmware blobs are proprietary.
        config.allowUnfree = true;
      };

      # self: modules/image.nix bakes the flake into /etc/nixos.
      specialArgs = { inherit self; } // specialArgs;

      modules = [ ../modules ] ++ modules;
    };
}
