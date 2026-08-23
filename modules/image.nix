# Produces config.system.build.shengImage: a single raw ext4 filesystem
# image plus an Android sparse-format copy, PARTLABEL-tagged, meant to be
# `fastboot flash`ed straight onto an existing Android GPT partition --
# exactly what the reference project's build-proper-rootfs.sh does
# (`truncate -s 10G rootfs.img && mkfs.ext4 rootfs.img`), just assembled
# from a NixOS closure instead of debootstrap.
#
# Deliberately NOT built on top of
# <nixpkgs>/nixos/modules/installer/sd-card/sd-image-aarch64.nix: that
# module partitions a whole SD card with a GPT + a FAT firmware/ESP
# partition, which this device doesn't have room for or need -- there's
# no SD card, just one existing partition on the device's own storage.
# Instead this calls nixos/lib/make-ext4-fs.nix directly, the same
# low-level helper sd-image.nix itself uses, for a single partition.
#
# BOOTSTRAP extlinux.conf: this writes a single fixed entry pointing at
# this build's own kernel/dtb/toplevel, because
# generic-extlinux-compatible's real installer enumerates
# /nix/var/nix/profiles/system-*-link and a freshly-built image has no
# such history yet.
#
# It is only ever the first boot's entry. sheng-nix-bootstrap.nix creates
# the system profile and then runs the real installer, which overwrites
# this file with a proper generation list -- so from the second boot
# onwards U-Boot's menu shows every generation.
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

      # Kept as a belt-and-braces fallback for U-Boot's own fallback path.
      # sheng.env's `bootlinux` boots /boot/Image with a hardcoded bootargs
      # carrying no init=, so the kernel's built-in search (/sbin/init,
      # /etc/init, /bin/init, /bin/sh) has to find this symlink. The normal
      # path is extlinux.conf below, which passes an explicit init=.
      ln -sf ${config.system.build.toplevel}/init ./files/sbin/init

      # Bootstrap boot entry, written by the SAME installer that runs at
      # activation time (../nixos/sheng-extlinux.nix), so the image and a
      # rebuilt system cannot drift in format.
      #
      # In this sandbox /nix/var/nix/profiles/system-*-link does not
      # exist, so its generation loop runs zero times: exactly one LABEL
      # and an empty sheng-bootmenu.env, which is the correct first-boot
      # state. sheng-nix-bootstrap.nix re-runs it after creating the
      # system profile, and from then on the list is real.
      ${config.sheng.boot.installer}/bin/sheng-install-boot \
        -d ./files/boot ${config.system.build.toplevel}

      # The flake itself, so the device can rebuild without a host.
      #
      # A mutable copy, not a store symlink: this is meant to be edited on
      # the tablet. flake.lock comes with it -- it is what pins nixpkgs, and
      # without it an on-device rebuild would float to whatever
      # nixos-unstable happens to be.
      #
      # nixpkgs' own source is already in the image (via nixpkgs.flake.source,
      # which also sets up /etc/nix/registry.json and NIX_PATH), so
      # `nixos-rebuild --flake /etc/nixos#sheng` resolves entirely offline.
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
        image auto-sized to its contents instead -- fine since
        fileSystems."/".autoResize is enabled, but a fixed size matching
        the target partition avoids any ambiguity when flashing.
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
        img="$out/sheng-rootfs.img"

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
        ''}

        echo "Converting to Android sparse format..."
        img2simg "$img" "$out/sheng-rootfs.sparse.img"
      '';
  };
}
