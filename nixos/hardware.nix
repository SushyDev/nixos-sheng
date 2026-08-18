# Always-on hardware support: kernel, device tree, bootloader, console,
# minimal base system, USB gadget serial for development. Unconditional --
# unlike xiaomi-sheng-services.nix, none of this is behind an option, since
# the device simply won't boot without it.
{ config, lib, pkgs, ... }:

{
  boot.kernelPackages = pkgs.linuxPackagesFor pkgs.shengKernel;

  hardware.deviceTree = {
    enable = true;
    filter = "sm8550-xiaomi-sheng.dtb";

    # mdss_dp0 (DP-altmode, board dts default status="okay") permanently
    # EPROBE_DEFERs on a Type-C retimer-switch that never resolves at this
    # sm8550-mainline commit -- and since it's a required component of
    # msm's aggregate KMS driver, that alone blocked the whole display
    # pipeline (no /dev/dri/card0 at all), including the internal MIPI-DSI
    # panel, which has nothing to do with DP. Board doesn't need USB-C
    # video-out for this image; disabling DP unblocks the panel.
    #
    # NB: the root `compatible` block is required -- nixpkgs'
    # apply_overlays.py silently skips ("...: incompatible") any overlay
    # whose own `compatible` doesn't intersect the target dtb's, and an
    # overlay with none matches *nothing*, not everything. A build with
    # this omitted "succeeds" while doing nothing; verify by decompiling
    # the shipped .dtb, not just a clean build.
    overlays = [{
      name = "disable-dp-altmode";
      filter = "sm8550-xiaomi-sheng.dtb";
      dtsText = ''
        /dts-v1/;
        /plugin/;
        / {
          compatible = "xiaomi,sheng", "qcom,sm8550";
        };
        &{/soc@0/display-subsystem@ae00000/displayport-controller@ae90000} {
          status = "disabled";
        };
      '';
    }];
  };

  # U-Boot on this device already reads /boot/extlinux/extlinux.conf off
  # the rootfs directly -- no boot.img/mkbootimg step needed.
  boot.loader.generic-extlinux-compatible.enable = true;

  boot.loader.grub.enable = false;

  # Genuinely initramfs-less boot, matching the reference project's own
  # confirmed-working configuration exactly (its build script's own words:
  # "root filesystem driver + UFS are built-in in this config ... boots
  # with no initramfs"). NixOS's default systemd-based stage-1 initrd
  # assumes it can resolve fileSystems."/" via udev inside the initrd and
  # emits `root=fstab` (relying on that initrd's embedded fstab) -- with
  # no initrd at all, that mechanism doesn't apply, so the kernel's own
  # native PARTLABEL GPT-parsing (no udev/userspace involved) is used
  # instead, exactly like the reference project's extlinux.conf.
  boot.initrd.enable = false;

  boot.consoleLogLevel = lib.mkDefault 7;
  boot.kernelParams = [
    "console=ttyMSM0,115200n8"
    "root=PARTLABEL=${config.sheng.rootfs.partlabel}"
    "rw"
    "rootwait"
  ];

  # PARTLABEL of the target Android partition this image gets flashed
  # onto -- reads config.sheng.rootfs.partlabel (defined in
  # rootfs/builder.nix) so this can never drift out of sync with what the
  # image itself is built/labeled for. The device= value here only needs
  # to be *some* valid path for NixOS's own bookkeeping (fstab, mount
  # unit dependency ordering); the kernel never actually resolves it at
  # boot since there's no initrd/udev to create the by-partlabel symlink
  # -- root is mounted directly via the root=PARTLABEL= kernel parameter
  # above instead.
  fileSystems."/" = {
    device = "/dev/disk/by-partlabel/${config.sheng.rootfs.partlabel}";
    fsType = "ext4";
    autoResize = true;
  };

  hardware.firmware = [ pkgs.shengPackages.sheng-firmware-blobs ];

  # --- USB gadget serial (development convenience) ---------------------
  # ttyGS0 exists automatically: kernel/default.nix sets
  # CONFIG_USB_G_SERIAL=y (built-in, auto-binds the UDC at boot). Don't
  # also add a ConfigFS-gadget systemd service here -- two gadget drivers
  # fighting over the same UDC re-enumerates the USB device mid-boot and
  # kills serial output entirely (confirmed on hardware).
  systemd.services."serial-getty@ttyGS0" = {
    enable = true;
    wantedBy = [ "multi-user.target" ];
  };

  # --- Minimal console-only base ----------------------------------------
  # No Wayland/Plasma yet -- lands at a framebuffer/serial getty prompt.
  services.xserver.enable = false;

  environment.systemPackages = with pkgs; [ vim curl wget htop git ];
  services.openssh.enable = true;
  networking.networkmanager.enable = true;
  networking.hostName = lib.mkDefault "sheng";

  # This kernel's config was never built with a firewall in mind and is
  # missing netfilter match modules NixOS's default rules need
  # (firewall.service fails: "Extension pkttype ... missing kernel
  # module?"). Private serial-console dev device, not internet-facing.
  networking.firewall.enable = false;

  # Random per-checkout password (not the reference build's hardcoded
  # "password"); initialHashedPassword so `passwd` on-device later isn't
  # clobbered by a rebuild. Change before sharing this repo/image.
  users.users.root.initialHashedPassword = "$6$aVNCmOu1k5I.kmYe$t/XqttCF23U3cOT8i7Oa2gc2FaXqk2DcdX8NEexSrz4TRUbPJ8h0faVQXJYMQA65IFJ3OXEHjGLvrh07f11sg1";
  users.mutableUsers = true;

  system.stateVersion = "24.11";
}
