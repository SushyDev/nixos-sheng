# shengSystem: nixosSystem with the sheng module already imported.
#
#   nixos-sheng.lib.shengSystem { modules = [ ./hosts/sheng.nix ]; }
#
# nixpkgs defaults to this flake's own input; to share one across a fleet,
# either use inputs.nixos-sheng.inputs.nixpkgs.follows or pass it here.
{ self }:

{
  shengSystem =
    {
      nixpkgs ? self.inputs.nixpkgs,
      modules ? [ ],
      specialArgs ? { },
    }:
    nixpkgs.lib.nixosSystem {
      specialArgs = {
        inherit self;
      }
      // specialArgs;
      modules = [ self.nixosModules.default ] ++ modules;
    };
}
