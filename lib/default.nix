# shengSystem: a nixosSystem preconfigured for the Xiaomi Pad 6S Pro.
#
#   nix-sheng.lib.shengSystem {
#     modules = [ ./hosts/sheng.nix ];
#   }
#
# nixpkgs defaults to this flake's own input, so a caller needs to pass
# nothing -- the same as nixpkgs.lib.nixosSystem. To share one nixpkgs
# across a fleet, either set
#
#   inputs.nixos-sheng.inputs.nixpkgs.follows = "nixpkgs";
#
# which is the idiomatic way and needs nothing here, or pass nixpkgs
# explicitly to override it. Either matters: the device needs a kernel and
# firmware that track nixpkgs, and a bump can break them.
{ self }:

{
  shengSystem =
    {
      nixpkgs ? self.inputs.nixpkgs,
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
