# Builds config.system.build.shengImage: a raw ext4 filesystem plus an
# Android sparse copy, to `fastboot flash userdata`.
#
# Not built on sd-image-aarch64.nix: that partitions a whole card with a
# GPT and a FAT ESP. This device has one existing partition. Calls
# make-ext4-fs.nix directly, the same helper sd-image uses.
#
# The extlinux.conf written here has a single entry, because the real
# installer enumerates /nix/var/nix/profiles/system-*-link and a fresh
# image has no history. nix-bootstrap.nix creates the profile on first
# boot and re-runs the installer, which replaces it with a real list.
{ self, config, lib, pkgs, modulesPath, ... }:

let
  cfg = config.sheng.rootfs;

  # nixos/lib/make-ext4-fs.nix auto-sizes the image to fit its contents
  # (+ slack) and has no fixed-size knob of its own -- $out is the raw
  # .img file directly. We grow/truncate to cfg.imageSize afterwards, and
  # produce an Android sparse copy alongside it, so flashing needs nothing
  # beyond what's already in this derivation's closure (no android-tools
  # dependency on the machine doing the flashing).
  rawImage = pkgs.callPackage "${modulesPath}/../lib/make-ext4-fs.nix" {
    storePaths = [ config.system.build.toplevel ];
    volumeLabel = cfg.partlabel;
    populateImageCommands = ''
      mkdir -p ./files/boot ./files/sbin

      kernelImage=${config.system.build.kernel}/${config.system.boot.loader.kernelFile}
      dtb=${config.hardware.deviceTree.package}/qcom/sm8550-xiaomi-sheng.dtb

      cp "$kernelImage" ./files/boot/Image
      cp "$dtb" ./files/boot/sm8550-xiaomi-sheng.dtb

      # sheng.env's rescue path boots /boot/Image with no init=, so the
      # kernel's built-in search must find this. nix-bootstrap.nix keeps
      # it current afterwards.
      ln -sf ${config.system.build.toplevel}/init ./files/sbin/init

      # Same installer that runs at activation, so image and rebuilt
      # system cannot drift in format.
      ${config.sheng.boot.installer}/bin/sheng-install-boot \
        -d ./files/boot ${config.system.build.toplevel}

      # The flake, so the device can rebuild without a host. A mutable
      # copy, not a store symlink: it is meant to be edited here.
      # flake.lock comes too, or an on-device rebuild floats to whatever
      # nixos-unstable is that day and rebuilds the world.
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
        PARTLABEL of the existing Android partition this image gets
        flashed onto (must match fileSystems."/".device in hardware.nix,
        which reads this same option). Default "userdata" replaces
        Android entirely (single-boot); set to "linux" for the reference
        project's non-destructive dual-boot convention instead (a spare
        partition carved out of userdata via TWRP beforehand).
      '';
    };

    imageSize = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = "10G";
      description = ''
        Fixed size to grow the image to after building (must be at least
        as large as the populated content). Set to null to leave the
        image auto-sized to its contents instead.

        Defaults to a fixed size, and measurement is why: img2simg drops
        the empty blocks either way, so the sparse image you actually
        flash is 2,479,710,700 bytes at "10G" against 2,479,241,764 at
        null -- a 0.02% difference, i.e. no saving in flash time at all.
        What the fixed size does buy is slack: 7.5G free on first boot
        rather than 160M. fileSystems."/".autoResize (x-systemd.growfs,
        since there is no initrd) should expand to the whole partition
        before anything needs the space, but if it ever does not, 160M is
        a bad place to land.
      '';
    };

    keepRawImage = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Also ship the raw ext4 image next to the Android sparse one.

        Off by default because nothing consumes it: flash-rootfs defaults
        to the sparse image and only accepts a raw one as a magic-sniffed
        fallback. Keeping it costs imageSize bytes of disk per fetch on
        the build host (10G, against 2.5G for the sparse image) for a file
        that is normally never opened. Turn it on to loopback-mount the
        filesystem and look inside.
      '';
    };
  };

  config = {
    system.build.shengImage = pkgs.runCommand "sheng-rootfs-images"
      {
        nativeBuildInputs = [ pkgs.e2fsprogs pkgs.android-tools ];
      }
      ''
        mkdir -p "$out"
        # Built in $TMPDIR and only installed into $out if asked for: the
        # raw image is an intermediate for img2simg, and at imageSize it
        # is four times the size of the thing anyone actually flashes.
        img="$TMPDIR/sheng-rootfs.img"

        cp --reflink=auto ${rawImage} "$img"
        chmod +w "$img"

        ${lib.optionalString (cfg.imageSize != null) ''
          echo "Growing image to ${cfg.imageSize}..."
          # truncate before resize2fs, not after: resize2fs needs the file
          # already at its final size to grow into. Doing it the other way
          # around shipped images with the ext4 error flag set (systemd-
          # growfs-root.service refusing to run at boot).
          truncate -s ${cfg.imageSize} "$img"
          e2fsck -fy "$img" || true
          resize2fs "$img" ${cfg.imageSize}

          # A single e2fsck pass after growing isn't enough: e2fsck's exit
          # code is 1 ("errors corrected") on the pass that actually fixes
          # something, not 0, and swallowing that with `|| true` shipped
          # images where resize2fs's newly-added (BLOCK_UNINIT, lazy-init)
          # block groups had a stale/incorrect bitmap checksum -- confirmed
          # on hardware as "EXT4-fs error ... ext4_validate_block_bitmap:
          # bad block bitmap checksum" from the kernel's own ext4lazyinit
          # thread a few seconds into boot, before growfs even ran, and as
          # systemd-growfs-root.service then failing with "Operation not
          # permitted" (the kernel refuses further resizes once the fs has
          # the error flag set). Loop until e2fsck itself reports a clean
          # pass (exit 0); fail the build loudly rather than ship an image
          # e2fsck never actually finished fixing.
        ''}

        # Unconditional: the imageSize = null path never resizes, but an
        # unverified image is not worth shipping either way, and on that
        # path this is a couple of seconds.
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
