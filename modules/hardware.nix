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

    # LOAD-BEARING for extlinux boot, not just documentation.
    #
    # generic-extlinux-compatible passes this through as the builder's -n
    # (nixos/modules/system/boot/loader/generic-extlinux-compatible/
    # default.nix). With it set, extlinux.conf gets an explicit
    #   FDT ../nixos/<dtbs>/qcom/sm8550-xiaomi-sheng.dtb
    # naming exactly the DTB built with the overlay below. Leave it unset
    # and the builder emits FDTDIR instead, leaving U-Boot to pick a DTB
    # by matching compatible strings -- which is not guaranteed to select
    # the overlaid one.
    name = "qcom/sm8550-xiaomi-sheng.dtb";

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

  # Bootloader lives in ./sheng-extlinux.nix, which writes
  # /boot/extlinux/extlinux.conf for U-Boot's `sysboot` and disables the
  # stock generic-extlinux-compatible module (which silently emits zero
  # entries on an initrd-less system -- see that file's header).

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

  # THIS IS NOW THE SINGLE SOURCE OF TRUTH for the kernel command line.
  #
  # These reach the kernel as extlinux.conf's APPEND line, which U-Boot's
  # `sysboot` applies along with the per-generation init=. They used to be
  # inert -- sheng.env built bootargs by hand -- so the two had to be kept
  # in sync manually. sheng.env's hardcoded string now survives only as
  # the fallback path for when extlinux.conf is missing or unparseable.
  #
  # console=tty0 + fbcon=map:0 is what puts the kernel log on the panel:
  # fbcon alone does not make it a printk target, tty0 as a console=
  # target is what does. Drop the pair and the log is serial-only, on a
  # board whose serial is not connected.
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
  # This kernel's .config has CONFIG_FW_LOADER_COMPRESS unset, so it can't
  # decompress the .zst firmware NixOS ships by default on 5.19+ kernels
  # -- request_firmware() would just fail to find e.g. amss.bin.zst under
  # its real (uncompressed) name. Blobs are small; skip compression.
  hardware.firmwareCompression = "none";

  # --- USB gadget serial (development convenience) ---------------------
  # ttyGS0 exists automatically: kernel/default.nix sets
  # CONFIG_USB_G_SERIAL=y (built-in, auto-binds the UDC at boot). Don't
  # also add a ConfigFS-gadget systemd service here -- two gadget drivers
  # fighting over the same UDC re-enumerates the USB device mid-boot and
  # kills serial output entirely (confirmed on hardware).
  # getty@tty1 / autovt@tty1: re-enabled. Was TEMPORARILY masked for the
  # same now-completed cont_splash investigation as kernel/default.nix's
  # DRM_MSM disable (see that file's comment) -- with DRM_MSM back on,
  # we want the on-screen login (fbcon via drm/msm's fbdev emulation)
  # back too, not just serial/ttyGS0.

  systemd.services."serial-getty@ttyGS0" = {
    enable = true;
    wantedBy = [ "multi-user.target" ];
    # Unset $TERM (referenced but never set by the base template on this
    # gadget tty) makes agetty hit "checkname failed: Operation not
    # permitted" a few seconds in and die -- confirmed on hardware.
    # Restart=always so a future USB re-enumeration/HUP on this tty
    # self-heals instead of leaving the console dead until someone SSHes
    # in to restart it by hand.
    environment.TERM = "vt102";
    serviceConfig.Restart = "always";
    serviceConfig.RestartSec = "1";
  };

  # hci0 (wcn7850) fully initializes on its own at the kernel level
  # (firmware loads, QCA setup completes) -- this is purely what starts
  # bluetoothd on top of it. Confirmed on hardware: without it,
  # bluetooth.service just sits inactive despite hci0 being ready.
  hardware.bluetooth.enable = false;

  # --- Minimal console-only base ----------------------------------------
  # No Wayland/Plasma yet -- lands at a framebuffer/serial getty prompt.
  services.xserver.enable = false;

  # busybox is included for its `devmem` applet -- reading physical
  # memory (e.g. the sheng_mdss pre-console breadcrumb region at
  # CONFIG_PRE_CON_BUF_ADDR, see drivers/video/qualcomm/sheng_mdss.c)
  # after a warm reset needs mmap-based /dev/mem access, which plain
  # `dd`/`cat` can't do for no-map reserved regions (EFAULT via the
  # read() path). Invoke as `busybox devmem <addr>` rather than relying
  # on PATH-shadowed applet symlinks, since this coreutils-overlapping
  # package isn't meant to replace the regular utilities here.
  environment.systemPackages = with pkgs; [ vim curl wget htop git busybox ];
  services.openssh.enable = true;
  networking.networkmanager.enable = true;
  networking.hostName = lib.mkDefault "sheng";

  # This kernel's config was never built with a firewall in mind and is
  # missing netfilter match modules NixOS's default rules need
  # (firewall.service fails: "Extension pkttype ... missing kernel
  # module?"). Private serial-console dev device, not internet-facing.
  networking.firewall.enable = false;

  # Plaintext "password" (matches the reference build) -- chosen over a
  # random one after two random passwords in a row failed to work over
  # the serial terminal (unclear whether that was a real password issue
  # or something else in the login path; "password" at least removes typos
  # as a variable). hashedPassword (not initialHashedPassword) so it's
  # deterministic on every boot regardless of "first boot" state. NOT
  # secure -- fine for this private dev device, change before sharing.
  users.users.root.hashedPassword = "$6$e/k7.7lhroPMA6hy$ysO.xH9hAm5y0NCdKQs4AAT0MQFy0kP7F6XpVIryRAN1wNHReXXHx21zdonHiXwKuynriN9UA.OQDhhz67atj/";
  users.mutableUsers = true;

  # Auto-login as root on every console -- the physical tty AND the serial
  # gettys (ttyGS0, the USB gadget exec.sh rides on, and ttyMSM0).
  #
  # This is a bring-up device rebooted dozens of times an hour, and typing
  # root/password at every boot is pure friction. Same security reasoning as
  # the plaintext password above: private dev device, no network exposure
  # (firewall disabled, not internet-facing). Remove both before sharing.
  #
  # services.getty.autologinUser covers getty@ and serial-getty@ alike, so
  # one setting handles tty1 and both serial consoles. Worth doing here
  # rather than at runtime: NixOS ships its getty ExecStart from a store-path
  # TEMPLATE drop-in (...-system-units/serial-getty@.service.d/overrides.conf)
  # which systemd applies AFTER anything in /run, and /etc is read-only -- so
  # an ad-hoc drop-in is loaded but silently loses to it.
  services.getty.autologinUser = "root";

  system.stateVersion = "24.11";
}
