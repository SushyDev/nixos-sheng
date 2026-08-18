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
# NOTE (v1 simplification): /boot/extlinux/extlinux.conf is written here
# with a single fixed boot entry pointing at this build's kernel/dtb,
# rather than going through generic-extlinux-compatible's generation-list
# installer (which expects a mutable /nix/var/nix/profiles/system-*-link
# history to enumerate, which a freshly-built image doesn't have). Once
# the base image boots, switching to on-device `nixos-rebuild boot` for
# multi-generation extlinux menus is a natural follow-up.
{ config, lib, pkgs, modulesPath, ... }:

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

      # U-Boot (../u-boot, board/qualcomm/sheng.env) loads Image + the dtb
      # directly and boots with a static, hardcoded bootargs -- it doesn't
      # read extlinux.conf, so there's no way to hand it a build-specific
      # init= (the nix store path changes every rebuild). Instead: no
      # init= at all (same as sheng.env's bootargs and Debian's own boot),
      # so the kernel's built-in fallback (/sbin/init, /etc/init,
      # /bin/init, /bin/sh, tried whenever no init= is set) finds this.
      ln -sf ${config.system.build.toplevel}/init ./files/sbin/init
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
          echo "Final filesystem check..."
          e2fsck -fy "$img" || true
        ''}

        echo "Converting to Android sparse format..."
        img2simg "$img" "$out/sheng-rootfs.sparse.img"
      '';
  };
}
