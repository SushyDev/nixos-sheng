# Mainline Linux kernel fork for the Xiaomi Pad 6S Pro ("sheng", SM8550P),
# tracking https://github.com/ianchb/sm8550-mainline.
#
# IMPORTANT: the config comes from https://github.com/ianchb/debian-sheng's
# own repo-root `sm8550.config` (9,372 lines, a genuinely complete,
# hand-maintained .config -- confirmed EXT4_FS=y, checked against the
# actual file backing the reference project's confirmed-working boot),
# NOT `sm8550-mainline`'s in-tree arch/arm64/configs/sm8550.config, which
# despite the identical filename is a completely different, much smaller
# (~80-line) kbuild config *fragment* meant to be merged onto arm64's
# generic defconfig. Using the in-tree fragment directly with `cp + make
# olddefconfig` (rather than merging it onto defconfig first) silently
# produces a kernel with no EXT4_FS support at all and was the root cause
# of an unbootable image -- these two "sm8550.config" files are not
# interchangeable despite the name coincidence. Recipe matches the
# reference project's own build.sh exactly: `cp sm8550.config .config &&
# make olddefconfig`, then our own additions merged on top.
{ lib
, stdenv
, fetchFromGitHub
, fetchurl
, linuxManualConfig
, buildPackages
, flex
, bison
, bc
, perl
, python3
, elfutils
, openssl
, ncurses
  # linuxPackagesFor and other NixOS kernel plumbing call
  # kernel.override { kernelPatches = ...; features = ...; etc. } -- catch
  # and forward whatever extra args show up instead of declaring each one.
, ...
}@args:

let
  # Pinned to the tip of `sheng-7.2.0` as of 2026-08-18. That branch is a
  # rolling dev target, so re-pin periodically:
  #   curl -s https://api.github.com/repos/ianchb/sm8550-mainline/commits/sheng-7.2.0 | jq -r .sha
  src = fetchFromGitHub {
    owner = "ianchb";
    repo = "sm8550-mainline";
    rev = "005aa8ccae670a8e731a279e2a802ac75e1e662d";
    hash = "sha256-IGPK6s0gtPZ587NnLotFvDXx9IFWbo52PHjTNXQTQns=";
  };

  version = "7.2.0-sheng";

  # The real, complete base config (see note above) -- pinned to the
  # debian-sheng commit that last touched it as of 2026-08-18. Re-pin
  # periodically:
  #   curl -s https://api.github.com/repos/ianchb/debian-sheng/commits/master | jq -r .sha
  baseConfig = fetchurl {
    url = "https://raw.githubusercontent.com/ianchb/debian-sheng/940232a99ef3d5b7c3e7308a0ca367a809dcc799/sm8550.config";
    hash = "sha256-XEBixKV1QLAxQRtlK6cgKVXm3uarahL+dnr5MiurdI4=";
  };

  # Our own additions on top of the known-working base config:
  # - USB ConfigFS ACM/serial gadget + legacy USB_G_SERIAL: upstream
  #   sm8550.config doesn't enable either; USB_G_SERIAL is built-in and
  #   auto-binds the UDC at boot, giving ttyGS0 with no userspace step
  #   (see hardware.nix).
  # - GPIO_SHARED_PROXY=y (was =m upstream): matches the locally
  #   confirmed-working sm8550.config.
  # - TYPEC_MUX_PS5169 disabled: drivers/usb/typec/mux/ps5169.c at this
  #   commit fails to compile (missing gpio/consumer.h include, a real
  #   upstream source bug). Not needed for display/console/storage.
  ourConfigFragment = builtins.toFile "sheng-extra.config" ''
    CONFIG_USB_CONFIGFS_ACM=y
    CONFIG_USB_CONFIGFS_SERIAL=y
    CONFIG_USB_G_SERIAL=y
    CONFIG_GPIO_SHARED_PROXY=y
    # CONFIG_TYPEC_MUX_PS5169 is not set
  '';

  configfile = stdenv.mkDerivation {
    pname = "sheng-kernel-config";
    inherit version src;
    nativeBuildInputs = [ flex bison bc perl python3 elfutils openssl ncurses ];
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
  # Everything NixOS/linuxPackagesFor might pass via .override {...}
  # (kernelPatches, features, ...) that isn't one of this file's own
  # build-only inputs -- forward it through untouched.
  passthroughArgs = builtins.removeAttrs args [
    "fetchFromGitHub"
    "fetchurl"
    "linuxManualConfig"
    "buildPackages"
    "flex"
    "bison"
    "bc"
    "perl"
    "python3"
    "elfutils"
    "openssl"
    "ncurses"
  ];
in
linuxManualConfig (passthroughArgs // {
  inherit lib stdenv version src configfile;

  # sm8550.config sets CONFIG_LOCALVERSION="-sm8550", so the real
  # kernelrelease string is 7.2.0-sm8550, not 7.2.0-sheng.
  modDirVersion = "7.2.0-sm8550";

  allowImportFromDerivation = true;

  extraMeta = {
    branch = "sheng-7.2.0";
    description = "Mainline kernel for the Xiaomi Pad 6S Pro (sheng, SM8550P)";
  };
})
