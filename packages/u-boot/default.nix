# U-Boot for sheng, plus the Android boot.img ABL actually loads.
{
  lib,
  buildUBoot,
  zig,
  xxd,
  mk-boot-img,
  src,
  version ? "sheng",
}:

(buildUBoot {
  inherit src version;

  defconfig = "sm8550_defconfig";

  # The MDSS register sequencing is Zig. Passed as a make variable rather than
  # put on PATH, because nixpkgs' zig hook would replace buildPhase with `zig
  # build` and there is no build.zig here.
  extraMakeFlags = [ "ZIG=${lib.getExe zig}" ];

  filesToInstall = [
    "u-boot.bin"
    "u-boot-nodtb.bin"
    "u-boot-dtb.bin"
    "u-boot.dtb"
  ];

  extraMeta = {
    description = "U-Boot for the Xiaomi Pad 6S Pro (sheng, SM8550)";
    platforms = [ "aarch64-linux" ];
  };
}).overrideAttrs
  (old: {
    pname = "u-boot-sheng";

    nativeBuildInputs = old.nativeBuildInputs ++ [
      mk-boot-img # shared with `uboot build`, so both produce the same layout
      xxd # CONFIG_ENV_USE_DEFAULT_ENV_TEXT_FILE embeds sheng.env via xxd
    ];

    # zig writes caches relative to $HOME, which is not writable here.
    preBuild = ''
      export HOME=$TMPDIR
      export ZIG_GLOBAL_CACHE_DIR=$TMPDIR/zig-cache
      export ZIG_LOCAL_CACHE_DIR=$TMPDIR/zig-cache
    '';

    postInstall = ''
      mk-boot-img u-boot-dtb.bin u-boot.dtb "$out/boot.img"
    '';
  })
