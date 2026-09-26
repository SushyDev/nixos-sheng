# Writes /boot/extlinux/extlinux.conf and the menu file U-Boot imports. Forked
# from generic-extlinux-compatible, whose addEntry() skips initrd-less systems.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.sheng.boot;

  installer = pkgs.writeShellApplication {
    name = "sheng-install-boot";
    runtimeInputs = with pkgs; [
      coreutils
      gnused
      gawk
    ];
    runtimeEnv = {
      SHENG_BOOT_LIMIT = toString cfg.configurationLimit;
      SHENG_DTB_NAME = cfg.dtbName;
    };
    text = builtins.readFile ./install-boot.sh;
  };
in
{
  options.sheng.boot = {
    configurationLimit = lib.mkOption {
      type = lib.types.int;
      default = 10;
      description = "How many generations U-Boot's menu offers. bootmenu.c caps it at 99.";
    };

    dtbName = lib.mkOption {
      type = lib.types.str;
      default = "qcom/sm8550-xiaomi-sheng.dtb";
      description = "Device tree within the generation's `dtbs` directory, written into each FDT line.";
    };

    installer = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      description = "The installer, exposed so the image builder can run it at build time.";
    };
  };

  config = {
    sheng.boot.installer = installer;

    system.build.installBootLoader = lib.getExe installer;
    system.boot.loader.id = "sheng-extlinux";

    # Cannot be used here -- see the header.
    boot.loader.generic-extlinux-compatible.enable = false;
    boot.loader.grub.enable = false;
  };
}
