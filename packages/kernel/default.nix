# Mainline kernel for the Xiaomi Pad 6S Pro (sheng, SM8550P), tracking
# ianchb/sm8550-mainline.
#
# The base config is debian-sheng's repo-root sm8550.config, not the in-tree
# arch/arm64/configs/sm8550.config -- same name, but the in-tree one is a
# fragment meant to be merged onto defconfig, and using it directly yields a
# kernel with no EXT4_FS and no boot.
{
  lib,
  stdenv,
  fetchFromGitHub,
  fetchurl,
  linuxManualConfig,
  buildPackages,
  flex,
  bison,
  bc,
  perl,
  python3,
  elfutils,
  openssl,
  ncurses,
}:

let
  version = "7.2.2-sheng";

  src = fetchFromGitHub {
    owner = "ianchb";
    repo = "sm8550-mainline";
    rev = "ad75da348a020f0b7cb541ca2f06ab38cf77004d"; # tag 7.2.2
    hash = "sha256-ZZcBh6At2H4mpjK+hJe3JrUvTsujYdJFq9j7dJhS1kM=";
  };

  baseConfig = fetchurl {
    url = "https://raw.githubusercontent.com/ianchb/debian-sheng/d570156721cff0026a89596cdf2eb421fd04a434/sm8550.config";
    hash = "sha256-4hPYqTPCriFY1D/xo9Eot0UD1QgWNkNQOOhccE1EJW0=";
  };

  ourConfigFragment = builtins.toFile "sheng-extra.config" ''
    CONFIG_USB_CONFIGFS_ACM=y
    CONFIG_USB_CONFIGFS_SERIAL=y
    # =m, not =y: built in it auto-binds the UDC at boot, pinning the Type-C
    # port in peripheral mode for the life of the system.
    CONFIG_USB_G_SERIAL=m
    CONFIG_GPIO_SHARED_PROXY=y
    # Without this the ps5169 retimer never binds, the DP controller defers
    # forever, and msm_drm -- all components or none -- never completes.
    CONFIG_TYPEC_MUX_PS5169=y
    # /dev/mem carries the U-Boot pre-console log and the MDSS ring buffer, and
    # strict-devmem blocks both.
    # CONFIG_STRICT_DEVMEM is not set
    # CONFIG_IO_STRICT_DEVMEM is not set
  '';

  configfile = stdenv.mkDerivation {
    pname = "sheng-kernel-config";
    inherit version src;

    nativeBuildInputs = [
      flex
      bison
      bc
      perl
      python3
      elfutils
      openssl
      ncurses
    ];
    depsBuildBuild = [ buildPackages.stdenv.cc ];

    dontConfigure = true;
    dontBuild = true;

    installPhase = ''
      runHook preInstall

      export ARCH=arm64
      export KCONFIG_NOTIMESTAMP=1

      cp ${baseConfig} .config
      make olddefconfig

      ./scripts/kconfig/merge_config.sh -O . -m .config ${ourConfigFragment}
      make olddefconfig

      cp .config "$out"

      runHook postInstall
    '';
  };
in
linuxManualConfig {
  inherit
    lib
    stdenv
    version
    src
    configfile
    ;

  # sm8550.config sets CONFIG_LOCALVERSION="-sm8550", so kernelrelease is
  # 7.2.2-sm8550, not 7.2.2-sheng.
  modDirVersion = "7.2.2-sm8550";

  allowImportFromDerivation = true;

  extraMeta = {
    branch = "sheng-7.2.2";
    description = "Mainline kernel for the Xiaomi Pad 6S Pro (sheng, SM8550P)";
  };
}
