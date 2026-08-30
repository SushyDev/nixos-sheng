# Sheng kernel and vendor userspace, injected into pkgs so modules can use
# pkgs.shengKernel / pkgs.shengPackages.* instead of importing paths.
final: prev: {
  shengKernel = final.callPackage ./packages/kernel { };
  shengPackages = final.callPackage ./packages/firmware { };

  # SDDM's greeter reads its screen geometry once, so the Breeze wallpaper
  # keeps the size it had before the screen rotated. Patched through
  # qt6Packages: kdePackages only re-exports sddm, so overriding it there
  # leaves the wrapper on the stock build.
  qt6Packages = prev.qt6Packages.overrideScope (
    _: qprev: {
      sddm-unwrapped = qprev.sddm-unwrapped.overrideAttrs (old: {
        patches = (old.patches or [ ]) ++ [
          ./packages/sddm/0100-signal-a-geometry-change-when-the-screen-rotates.patch
        ];
      });
    }
  );
}
