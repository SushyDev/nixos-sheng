{
  config,
  lib,
  pkgs,
  ...
}:

{
  boot.kernelPackages = pkgs.linuxPackagesFor pkgs.shengKernel;

  hardware.deviceTree = {
    enable = true;
    filter = "sm8550-xiaomi-sheng.dtb";
    name = "qcom/sm8550-xiaomi-sheng.dtb";
  };

  boot.initrd.enable = false;

  boot.consoleLogLevel = lib.mkDefault 4;
  boot.kernelParams = [
    "console=ttyMSM0,115200n8"
    "console=tty0"
    "fbcon=map:0"
    "root=PARTLABEL=${config.sheng.rootfs.partlabel}"
    "rw"
    "rootwait"
    "log_buf_len=8M"

    # The monitor hub fails its first control transfer with EIO. Neither of
    # these fixes it, but autosuspend is pointless on a bus-powered hub.
    "usbcore.quirks=05e3:0610:k"
    "usbcore.autosuspend=-1"
  ];

  fileSystems."/" = {
    device = "/dev/disk/by-partlabel/${config.sheng.rootfs.partlabel}";
    fsType = "ext4";
    autoResize = true;
  };

  hardware.firmware = [ pkgs.shengPackages.sheng-firmware-blobs ];
  # No CONFIG_FW_LOADER_COMPRESS, so the kernel cannot read NixOS's .zst.
  hardware.firmwareCompression = "none";

  # This kernel has no netfilter match modules; leaving the firewall on fails
  # activation.
  networking.firewall.enable = lib.mkDefault false;
}
