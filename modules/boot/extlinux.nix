# Writes /boot/extlinux/extlinux.conf and the menu file U-Boot imports. Forked
# from generic-extlinux-compatible, whose builder skips any generation without
# an initrd -- which is every generation here.
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
      SHENG_DTB_NAME = config.hardware.deviceTree.name;
    };
    text = builtins.readFile ./install-boot.sh;
  };
in
{
  imports = [
    (lib.mkRenamedOptionModule [ "sheng" "boot" "dtbName" ] [ "hardware" "deviceTree" "name" ])
  ];

  options.sheng.boot = {
    configurationLimit = lib.mkOption {
      type = lib.types.int;
      default = 10;
      description = "How many generations U-Boot's menu offers. bootmenu.c caps it at 99.";
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

    boot.loader.generic-extlinux-compatible.enable = false;
    boot.loader.grub.enable = false;
  };
}
