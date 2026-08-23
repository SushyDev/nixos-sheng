# U-Boot for sheng, plus the Android boot.img ABL actually loads.
{
  lib,
  buildUBoot,
  zig,
  android-tools,
  src,
  version ? "sheng",
}:

let
  # ABL rejects anything else. Offsets and page size come from the stock
  # boot.img header.
  mkbootimgArgs = [
    "--kernel u-boot-dtb.bin"
    "--dtb u-boot.dtb"
    "--cmdline 'console=ttyMSM0,115200n8 console=ttyGS0,115200n8 g_serial.use_acm=1 root=PARTLABEL=userdata'"
    "--base 0x00000000"
    "--kernel_offset 0x00008000"
    "--tags_offset 0x01e00000"
    "--pagesize 4096"
    "--header_version 2"
    "--id"
  ];
in
(buildUBoot {
  inherit src version;

  defconfig = "sm8550_defconfig";

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

    # zig: the MDSS driver's register sequencing is Zig, built by
    # drivers/video/qualcomm/Makefile via scripts/Makefile.zig.
    # android-tools: mkbootimg.
    nativeBuildInputs = old.nativeBuildInputs ++ [
      zig
      android-tools
    ];

    # Zig writes its cache to $HOME.
    preBuild = ''
      export HOME=$TMPDIR
    '';

    postInstall = ''
      mkbootimg ${lib.concatStringsSep " " mkbootimgArgs} -o "$out/boot.img"
    '';
  })
