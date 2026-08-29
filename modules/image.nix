# Builds config.system.build.shengImage: a raw ext4 filesystem plus an Android
# sparse copy, to `fastboot flash userdata`. Calls make-ext4-fs.nix directly
# rather than building on sd-image-aarch64.nix, which would partition a whole
# card with a GPT and an ESP; this device has one existing partition.
{
  self,
  config,
  lib,
  pkgs,
  modulesPath,
  ...
}:

let
  cfg = config.sheng.rootfs;

  rawImage = pkgs.callPackage "${modulesPath}/../lib/make-ext4-fs.nix" {
    storePaths = [ config.system.build.toplevel ];
    volumeLabel = cfg.partlabel;
    populateImageCommands = ''
      mkdir -p ./files/boot ./files/sbin

      kernelImage=${config.system.build.kernel}/${config.system.boot.loader.kernelFile}
      dtb=${config.hardware.deviceTree.package}/qcom/sm8550-xiaomi-sheng.dtb

      cp "$kernelImage" ./files/boot/Image
      cp "$dtb" ./files/boot/sm8550-xiaomi-sheng.dtb

      ln -sf ${config.system.build.toplevel}/init ./files/sbin/init

      ${config.sheng.boot.installer}/bin/sheng-install-boot \
        -d ./files/boot ${config.system.build.toplevel}

      # A mutable copy, so the device can rebuild without a host.
      mkdir -p ./files/etc/nixos
      cp -r --no-preserve=mode,ownership ${self}/. ./files/etc/nixos/
    '';
  };
in
{
  options.sheng.rootfs = {
    partlabel = lib.mkOption {
      type = lib.types.str;
      default = "userdata";
      description = ''
        PARTLABEL of the existing Android partition this image gets flashed
        onto. The default replaces Android entirely; set it to "linux" for the
        reference project's dual-boot convention.
      '';
    };

    imageSize = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Fixed size to grow the image to, or null to leave it auto-sized.

        Leave it null. A fixed size corrupts the filesystem: resize2fs writes
        the block groups it adds with bitmap checksums the kernel rejects,
        while build-time e2fsck reports the image clean, so nothing catches it
        until the device boots and refuses every later resize -- including the
        growfs that would have claimed the rest of the partition. It buys
        nothing either, since img2simg drops the empty blocks anyway.
      '';
    };

    keepRawImage = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Also ship the raw ext4 image next to the Android sparse one, to
        loopback-mount and look inside. Off by default because nothing
        consumes it and it costs imageSize bytes per fetch.
      '';
    };
  };

  config = {
    system.build.shengImage =
      pkgs.runCommand "sheng-rootfs-images"
        {
          nativeBuildInputs = [
            pkgs.e2fsprogs
            pkgs.android-tools
          ];
        }
        ''
          mkdir -p "$out"
          img="$TMPDIR/sheng-rootfs.img"

          cp --reflink=auto ${rawImage} "$img"
          chmod +w "$img"

          ${lib.optionalString (cfg.imageSize != null) ''
            # Check BEFORE truncating, which cannot refuse a too-small size.
            e2fsck -fy "$img" || true
            min_blocks="$(resize2fs -P "$img" 2>/dev/null | awk '{ print $NF }')"
            want_blocks=$(( $(numfmt --from=iec ${cfg.imageSize}) / 4096 ))
            if [ "$want_blocks" -lt "$min_blocks" ]; then
              echo "sheng.rootfs.imageSize is ${cfg.imageSize}, but this configuration needs at least" >&2
              echo "$(( (min_blocks * 4096 + 1073741823) / 1073741824 ))G of filesystem to hold it." >&2
              echo "Raise sheng.rootfs.imageSize, or set it to null to auto-size to the contents." >&2
              exit 1
            fi

            echo "Growing image to ${cfg.imageSize}..."
            truncate -s ${cfg.imageSize} "$img"
            resize2fs "$img" ${cfg.imageSize}
          ''}

          # e2fsck exits 1 on the pass that fixes something, so loop rather than
          # swallow that with `|| true` and ship an image it never finished.
          echo "Final filesystem check..."
          clean=0
          for i in 1 2 3 4; do
            if e2fsck -fy "$img"; then
              echo "e2fsck reported clean on pass $i"
              clean=1
              break
            fi
            echo "e2fsck pass $i made changes, re-checking..."
          done
          if [ "$clean" != 1 ]; then
            echo "e2fsck did not converge to clean after 4 passes -- refusing to ship this image" >&2
            exit 1
          fi

          echo "Converting to Android sparse format..."
          img2simg "$img" "$out/sheng-rootfs.sparse.img"

          ${lib.optionalString cfg.keepRawImage ''
            mv "$img" "$out/sheng-rootfs.img"
          ''}
        '';
  };
}
