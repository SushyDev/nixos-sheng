# Kernel, device tree, console, base system. Unconditional: the device
# does not boot without it.
{ config, lib, pkgs, ... }:

{
  boot.kernelPackages = pkgs.linuxPackagesFor pkgs.shengKernel;

  hardware.deviceTree = {
    enable = true;
    filter = "sm8550-xiaomi-sheng.dtb";

    # Becomes extlinux.conf's FDT line, naming the DTB built with the
    # overlay below. Unset, the installer emits FDTDIR and U-Boot picks a
    # DTB by compatible string, which need not be the overlaid one.
    name = "qcom/sm8550-xiaomi-sheng.dtb";

    # mdss_dp0 EPROBE_DEFERs forever on a Type-C retimer that never
    # resolves. It is a required component of msm's aggregate KMS driver,
    # so that alone leaves no /dev/dri/card0 at all -- including the
    # internal DSI panel. No USB-C video-out needed here.
    #
    # The root `compatible` block is required. apply_overlays.py silently
    # skips an overlay whose compatible does not intersect the target
    # dtb's, and one with none matches nothing. Omitting it builds clean
    # and does nothing; check by decompiling the shipped .dtb.
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

  # Bootloader is ./extlinux.nix.

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

  # The kernel command line. Reaches the kernel as extlinux.conf's APPEND
  # line; sheng.env's copy is only the fallback path.
  #
  # console=tty0 + fbcon=map:0 puts the kernel log on the panel. fbcon
  # alone is not a printk target; tty0 as a console= target is. Without
  # the pair the log is serial-only, and serial is not connected.
  boot.consoleLogLevel = lib.mkDefault 4;
  boot.kernelParams = [
    "console=ttyMSM0,115200n8"
    "console=ttyGS0"
    "console=tty0"
    "fbcon=map:0"
    "root=PARTLABEL=${config.sheng.rootfs.partlabel}"
    "rw"
    "rootwait"
    "log_buf_len=8M"
  ];

  # device= is only for NixOS bookkeeping (fstab, mount ordering). The
  # kernel never resolves it: with no initrd there is no udev to create
  # the by-partlabel symlink, so root comes from root=PARTLABEL= above.
  # partlabel is shared with the image builder so the two cannot drift.
  fileSystems."/" = {
    device = "/dev/disk/by-partlabel/${config.sheng.rootfs.partlabel}";
    fsType = "ext4";
    autoResize = true;
  };

  hardware.firmware = [ pkgs.shengPackages.sheng-firmware-blobs ];
  # CONFIG_FW_LOADER_COMPRESS is unset in this kernel, so request_firmware()
  # cannot read the .zst NixOS ships by default. Blobs are small.
  hardware.firmwareCompression = "none";

  # ttyGS0 comes from CONFIG_USB_G_SERIAL=y, which auto-binds the UDC at
  # boot. Do not add a ConfigFS gadget service as well: two gadget drivers
  # on one UDC re-enumerate mid-boot and kill serial output.

  systemd.services."serial-getty@ttyGS0" = {
    enable = true;
    wantedBy = [ "multi-user.target" ];
    # The base template references $TERM but never sets it on this tty;
    # unset, agetty dies with "checkname failed". Restart=always so a USB
    # re-enumeration does not leave the console dead.
    environment.TERM = "vt102";
    serviceConfig.Restart = "always";
    serviceConfig.RestartSec = "1";
  };

  # hci0 comes up on its own; this only starts bluetoothd on top of it.
  hardware.bluetooth.enable = false;

  # Console only; lands at a getty prompt.
  services.xserver.enable = false;

  # busybox is here for `devmem`: reading no-map reserved regions needs
  # mmap-based /dev/mem, which dd and cat cannot do (EFAULT). Call it as
  # `busybox devmem <addr>`, not via applet symlinks.
  environment.systemPackages = with pkgs; [ vim curl wget htop git busybox ];
  services.openssh.enable = true;
  networking.networkmanager.enable = true;
  networking.hostName = lib.mkDefault "sheng";

  # This kernel lacks the netfilter match modules NixOS's default rules
  # need, so firewall.service fails. Private dev device.
  networking.firewall.enable = false;

  # Password is "password". hashedPassword, not initialHashedPassword, so
  # it is the same on every boot. NOT SECURE -- change before sharing.
  users.users.root.hashedPassword = "$6$e/k7.7lhroPMA6hy$ysO.xH9hAm5y0NCdKQs4AAT0MQFy0kP7F6XpVIryRAN1wNHReXXHx21zdonHiXwKuynriN9UA.OQDhhz67atj/";
  users.mutableUsers = true;

  # Covers getty@ and serial-getty@ alike, so tty1 and both serial
  # consoles autologin. Must be set here: NixOS's getty ExecStart comes
  # from a store-path drop-in that systemd applies after anything in /run,
  # so a runtime drop-in loses to it. NOT SECURE -- change before sharing.
  services.getty.autologinUser = "root";

  system.stateVersion = "24.11";
}
