final: prev: {
  shengKernel = final.callPackage ./packages/kernel { };
  shengPackages = final.callPackage ./packages/firmware { };

  # SDDM with the sheng patches (wallpaper geometry on rotation, fingerprint
  # beside the password prompt). Its own attribute rather than a global
  # qt6Packages override, so only modules/greeter.nix opts into it.
  # kdePackages just re-exports sddm, so the scope to patch is qt6Packages.
  shengSddm =
    (final.qt6Packages.overrideScope (
      _: qprev: {
        sddm-unwrapped = qprev.sddm-unwrapped.overrideAttrs (old: {
          patches = (old.patches or [ ]) ++ [
            ./packages/sddm/0100-signal-a-geometry-change-when-the-screen-rotates.patch
            ./packages/sddm/0101-verify-a-fingerprint-alongside-the-password-prompt.patch
          ];
        });
      }
    )).sddm;
}
