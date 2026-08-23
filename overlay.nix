# Sheng kernel and vendor userspace, injected into pkgs so modules can use
# pkgs.shengKernel / pkgs.shengPackages.* instead of importing paths.
final: prev: {
  shengKernel = final.callPackage ./packages/kernel { };
  shengPackages = final.callPackage ./packages/firmware { };
}
