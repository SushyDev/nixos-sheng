# Mainline kernel for the Xiaomi Pad 6S Pro (sheng, SM8550P), tracking
# ianchb/sm8550-mainline. Both sources are flake inputs (kernel-src,
# kernel-config), so a local tree is one --override-input away.
#
# The base config is debian-sheng's repo-root sm8550.config, not the in-tree
# arch/arm64/configs/sm8550.config -- same name, but the in-tree one is a
# fragment meant to be merged onto defconfig, and using it directly yields a
# kernel with no EXT4_FS and no boot.
{
  lib,
  stdenv,
  linuxManualConfig,
  src,
  baseConfig,
  buildPackages,
  flex,
  bison,
  bc,
  perl,
  python3,
  elfutils,
  openssl,
  ncurses,
  # NixOS's boot.kernelPackages re-overrides every kernel with features,
  # randstructSeed and kernelPatches, all of which belong to linuxManualConfig.
  # kernelPatches is read out of args rather than declared, or callPackage fills
  # it from pkgs.kernelPatches -- an attrset, where a list is wanted.
  features ? { },
  randstructSeed ? "",
  ...
}@args:

let
  # Read off the tree and the config rather than hardcoded, so bumping either
  # input is the whole upgrade. Both are store paths already: no IFD.
  lines = lib.splitString "\n" (builtins.readFile "${src}/Makefile");
  makeVar =
    name: lib.trim (lib.removePrefix "${name} =" (lib.findFirst (lib.hasPrefix "${name} =") "" lines));
  kernelVersion = "${makeVar "VERSION"}.${makeVar "PATCHLEVEL"}.${makeVar "SUBLEVEL"}${makeVar "EXTRAVERSION"}";

  localVersion = lib.removeSuffix "\"" (
    lib.removePrefix "CONFIG_LOCALVERSION=\"" (
      lib.findFirst (lib.hasPrefix "CONFIG_LOCALVERSION=\"") "" (
        lib.splitString "\n" (builtins.readFile baseConfig)
      )
    )
  );

  version = "${kernelVersion}-sheng";

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
    # The NixOS nftables firewall's reverse-path check.
    CONFIG_NFT_FIB_INET=m
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

      # olddefconfig drops an option whose dependencies are unmet, silently.
      grep '^CONFIG_' ${ourConfigFragment} | while read -r want; do
        grep -qxF "$want" .config || { echo "kernel config lost: $want" >&2; exit 1; }
      done
      sed -n 's/^# \(CONFIG_[A-Z0-9_]*\) is not set$/\1/p' ${ourConfigFragment} | while read -r off; do
        ! grep -q "^$off=" .config || { echo "kernel config still sets $off" >&2; exit 1; }
      done

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
    features
    randstructSeed
    ;

  # Everything in ./patches, in filename order. Each file says what it fixes.
  kernelPatches =
    map (name: {
      name = lib.removeSuffix ".patch" name;
      patch = ./patches + "/${name}";
    }) (builtins.attrNames (builtins.readDir ./patches))
    ++ (args.kernelPatches or [ ]);

  # kernelrelease comes from CONFIG_LOCALVERSION ("-sm8550"), not "-sheng".
  modDirVersion = kernelVersion + localVersion;

  allowImportFromDerivation = true;

  extraMeta = {
    description = "Mainline kernel for the Xiaomi Pad 6S Pro (sheng, SM8550P)";
  };
}
