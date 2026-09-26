# The development shell for the whole workspace:
#
#   <workspace>/
#   ├── nixos/        this repository
#   ├── u-boot/       SushyDev/u-boot, branch xiaomi-sheng
#   ├── kernel/       optional sm8550-mainline checkout, for --local-kernel
#   ├── references/   read-only upstream clones (`refs sync`)
#   └── sheng-devkey  SSH key the device trusts
#
# `devenv shell`, or direnv via .envrc. Run `sheng-help` for the commands.
{ pkgs, config, ... }:

let
  # flake.lock's nixpkgs, not devenv's, so zig and the cross compiler here are
  # the ones `nix build .#u-boot` uses. Zig breaks its language between minors.
  lock = builtins.fromJSON (builtins.readFile ./flake.lock);
  flakePkgs = import (builtins.fetchTree lock.nodes.nixpkgs.locked) {
    inherit (pkgs.stdenv.hostPlatform) system;
  };
  scripts = import ./scripts { pkgs = flakePkgs; };

  root = config.devenv.root;
  workspace = builtins.dirOf root;
in
{
  env = {
    SHENG_ROOT = root;
    SHENG_WORKSPACE = workspace;
    SHENG_OUT = "${root}/out";
    SHENG_REFS_LIST = "${root}/dev/references.txt";
    # Absolute, so the device scripts work from any directory in the workspace.
    SHENG_KEY = "${workspace}/sheng-devkey";
    SHENG_IP_CACHE = "${workspace}/.sheng-ip";
  };

  packages =
    builtins.attrValues scripts.packages
    ++ scripts.ubootToolchain
    ++ [
      flakePkgs.android-tools
      flakePkgs.tio
      flakePkgs.git
      flakePkgs.nixfmt
      flakePkgs.shellcheck
    ];

  scripts = {
    # exec, read-blackbox and capture-linux-dpu talk to this socket.
    serial.exec = ''
      rm -f /tmp/nixos-socket
      exec tio -m INLCRNL -S unix:/tmp/nixos-socket "''${1:-$(ls /dev/cu.usbmodem* | head -1)}"
    '';

    workspace-init.exec = ''
      set -e
      cd "$SHENG_WORKSPACE"
      [ -d u-boot/.git ] || git clone -b xiaomi-sheng git@github.com:SushyDev/u-boot.git u-boot
      [ -e .envrc ] || { cp "$SHENG_ROOT/dev/workspace.envrc" .envrc && direnv allow . 2>/dev/null || true; }
      [ -e sheng-devkey ] || echo "no sheng-devkey yet: ssh-keygen -t ed25519 -N ''' -f $SHENG_WORKSPACE/sheng-devkey"
      refs sync
    '';

    sheng-help.exec = ''
      cat <<'HELP'
      U-Boot (fast loop, native cross build of ../u-boot)
        uboot build [--debug]       -> out/boot.img, prints size delta and sheng.b= tag
        uboot menuconfig | savedefconfig | clean
        flash-uboot [img]           write boot_a/boot_b over SSH on a running device, reboot
        fastboot-flash [img]        same, from fastboot mode

      NixOS (aarch64-linux docker builder, cached kernel)
        builder build <attr>        attrs: nixos u-boot kernel <firmware pkgs>
        builder fetch <attr>        build and copy into out/
          --local-uboot             use ../u-boot as on disk
          --local-kernel            use ../kernel at its checked-out branch (committed only)
        builder shell | run <cmd> | status | down
        flash-rootfs [img]          userdata from fastboot mode (destructive, asks)

      Device
        find-sheng  sheng-mdss-status  soak [n]
        serial [dev]                tio bridge on /tmp/nixos-socket, for:
        exec '<cmd>'  read-blackbox [out]  capture-linux-dpu [blackbox]

      Workspace
        refs sync | status          update ../references from dev/references.txt
        workspace-init              clone u-boot, install the workspace .envrc, sync refs
      HELP
    '';
  };

  enterShell = ''
    echo "sheng: workspace $SHENG_WORKSPACE -- run sheng-help for commands"
  '';
}
