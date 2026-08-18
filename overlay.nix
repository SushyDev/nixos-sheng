# Injects the sheng-specific kernel and vendor userspace packages into pkgs,
# so NixOS modules reference them the normal overlay way (pkgs.shengKernel,
# pkgs.shengPackages.*) rather than importing paths directly.
final: prev: {
  shengKernel = final.callPackage ./kernel { };
  shengPackages = final.callPackage ./firmware { };
}
