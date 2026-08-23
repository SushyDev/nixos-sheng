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

    # There used to be a disable-dp-altmode overlay here, turning off
    # displayport-controller@ae90000 because mdss_dp0 EPROBE_DEFERred
    # forever on a Type-C retimer nothing provided -- and since it is a
    # component of msm's aggregate KMS driver, that left no
    # /dev/dri/card0 at all, internal panel included.
    #
    # That reason is gone: CONFIG_TYPEC_MUX_PS5169 is enabled and the
    # driver binds (/sys/bus/i2c/devices/3-0028 -> ps5169). Tested on
    # hardware by booting the un-overlaid DTB -- the panel comes up
    # normally and DRM gains card0-DP-1 alongside card0-DSI-1.
    #
    # Keeping it was expensive in a non-obvious way. The sound node's
    # dai-links include DisplayPort Playback, and ONE unresolvable link
    # fails the whole card:
    #
    #   platform sound: deferred probe pending: snd-sc8280xp:
    #     DisplayPort Playback: codec dai not found
    #
    # so /proc/asound/cards read "no soundcards" -- no speakers and no
    # microphone -- as a side effect of disabling a display feature.
    # With DP enabled the card probes: snd-sc8280xp binds and
    # "0 [XiaomiPad6SPro]: sm8550" appears.
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
    # console=ttyGS0 is added by serial-console.nix when that is enabled.
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

  # The ttyGS0 serial gadget console lives in serial-console.nix and is
  # off by default: binding a gadget to the UDC keeps the Type-C port in
  # peripheral mode, which costs USB host mode (hubs, keyboards, DP alt).

  # hci0 comes up on its own; this only starts bluetoothd on top of it --
  # and without bluetoothd the adapter is invisible to every desktop, so
  # Bluetooth looks unsupported when the hardware is in fact working.
  # mkDefault so a headless build can turn it back off.
  hardware.bluetooth.enable = lib.mkDefault true;

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

  # mkDefault so a downstream host config can pin its own -- this is a
  # module other people build systems from, and stateVersion is a property
  # of the install, not of the hardware.
  #
  # 26.11 matches the nixpkgs this flake locks. It is deliberately NOT the
  # usual "never change this" case: nothing has been installed from an
  # older release, the value was only ever a placeholder, and flashing
  # userdata wipes the state it would otherwise be protecting.
  system.stateVersion = lib.mkDefault "26.11";
}
