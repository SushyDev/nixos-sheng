{
  config,
  lib,
  pkgs,
  ...
}:

{
  imports = [
    ./audio.nix
    ./camera.nix
    ./input.nix
    ./power.nix
    ./qtee.nix
    ./sensors.nix
    ./wireless.nix
  ];

  options.sheng.vendor.enable = lib.mkEnableOption "the Xiaomi/Qualcomm vendor userspace" // {
    default = true;
  };

  config = {
    nixpkgs.hostPlatform = lib.mkDefault "aarch64-linux";
    # The firmware, the QTEE runtime and the charger daemons are proprietary.
    nixpkgs.config.allowUnfree = true;

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
    ];

    fileSystems."/" = {
      device = "/dev/disk/by-partlabel/${config.sheng.rootfs.partlabel}";
      fsType = "ext4";
      autoResize = true;
    };

    hardware.firmware = [ pkgs.shengPackages.sheng-firmware-blobs ];
    # No CONFIG_FW_LOADER_COMPRESS, so the kernel cannot read NixOS's .zst.
    hardware.firmwareCompression = "none";

    # The kernel lacks the xt_* matches iptables rules need, but has nft_fib.
    networking.nftables.enable = lib.mkDefault true;
  };
}
