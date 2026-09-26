# config.system.build.shengImage: the rootfs as an Android sparse image, to
# `fastboot flash userdata`. system.build.shengRawImage is the ext4 image it is
# made from, to loopback-mount.
{
  config,
  lib,
  pkgs,
  modulesPath,
  ...
}:

let
  cfg = config.sheng.rootfs;
  dtb = config.hardware.deviceTree.name;

  # Auto-sized to the contents; the device grows it on first boot
  # (fileSystems."/".autoResize).
  rawImage = pkgs.callPackage "${modulesPath}/../lib/make-ext4-fs.nix" {
    storePaths = [ config.system.build.toplevel ];
    volumeLabel = cfg.partlabel;
    populateImageCommands = ''
      mkdir -p ./files/boot ./files/sbin

      # U-Boot's rescue path when extlinux.conf is unusable.
      cp ${config.system.build.kernel}/${config.system.boot.loader.kernelFile} ./files/boot/Image
      cp ${config.hardware.deviceTree.package}/${dtb} ./files/boot/${baseNameOf dtb}

      ln -sf ${config.system.build.toplevel}/init ./files/sbin/init

      ${lib.getExe config.sheng.boot.installer} -d ./files/boot ${config.system.build.toplevel}

      ${lib.optionalString (cfg.etcNixosSource != null) ''
        mkdir -p ./files/etc/nixos
        cp -r --no-preserve=mode,ownership ${cfg.etcNixosSource}/. ./files/etc/nixos/
      ''}
    '';
  };
in
{
  imports = [
    (lib.mkRemovedOptionModule [ "sheng" "rootfs" "imageSize" ] ''
      A fixed size corrupted the filesystem: resize2fs wrote block groups whose
      bitmap checksums the kernel rejects. The image auto-sizes and grows on
      the device instead.
    '')
    (lib.mkRemovedOptionModule [
      "sheng"
      "rootfs"
      "keepRawImage"
    ] "Build system.build.shengRawImage for the raw ext4 image.")
  ];

  options.sheng.rootfs = {
    etcNixosSource = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      example = lib.literalExpression "inputs.self";
      description = ''
        Flake source to copy into /etc/nixos inside the image, so the device
        can {command}`nixos-rebuild` itself with no host attached. Null ships
        no /etc/nixos; point it at your own flake.
      '';
    };

    partlabel = lib.mkOption {
      type = lib.types.str;
      default = "userdata";
      description = ''
        PARTLABEL of the existing Android partition this image gets flashed
        onto. The default replaces Android entirely; "linux" is the reference
        project's dual-boot convention.
      '';
    };
  };

  config.system.build = {
    shengRawImage = rawImage;

    shengImage =
      pkgs.runCommand "sheng-rootfs-images"
        {
          nativeBuildInputs = [
            pkgs.android-tools
            pkgs.e2fsprogs
          ];
        }
        ''
          # make-ext4-fs only fscks before its final resize2fs (nixpkgs#125121).
          # Read-only: a repaired image is not the one that was built.
          e2fsck -fn ${rawImage}
          mkdir -p "$out"
          img2simg ${rawImage} "$out/sheng-rootfs.sparse.img"
        '';
  };
}
