# Host-side tools: flake apps (`nix run .#<name>`) and the devenv shell's PATH.
# Everything here runs on the machine you develop from, never on the device.
{ pkgs }:

let
  inherit (pkgs) lib;

  cross = pkgs.pkgsCross.aarch64-multiplatform;

  mk =
    name: runtimeInputs:
    pkgs.writeShellApplication {
      inherit name runtimeInputs;
      text = builtins.readFile (./. + "/${name}");
    };

  mkPython =
    name: runtimeInputs:
    pkgs.runCommand name
      {
        nativeBuildInputs = [
          pkgs.python3
          pkgs.makeWrapper
        ];
        meta.mainProgram = name;
      }
      ''
        install -Dm755 ${./.}/${name} $out/bin/${name}
        patchShebangs $out/bin/${name}
        ${lib.optionalString (runtimeInputs != [ ]) ''
          wrapProgram $out/bin/${name} \
            --prefix PATH : ${lib.makeBinPath runtimeInputs}
        ''}
      '';

  find-sheng = mk "find-sheng" [
    pkgs.openssh
    pkgs.netcat
  ];

  # Its own derivation, so read-blackbox cannot find it as a sibling.
  exec = mkPython "exec" [ ];

  mk-boot-img = mk "mk-boot-img" [ pkgs.android-tools ];

  # What U-Boot's own build needs, host tools included. Shared with the devenv
  # so `make menuconfig` in ../u-boot works from the same shell.
  ubootToolchain = [
    cross.stdenv.cc
    # Pinned by minor: Zig changes its language between them. Keep in step
    # with the u-boot package in flake.nix.
    pkgs.zig_0_16
    pkgs.gnumake
    pkgs.bison
    pkgs.flex
    pkgs.bc
    pkgs.dtc
    pkgs.openssl
    pkgs.ncurses
    pkgs.pkg-config
    pkgs.gnutls
    pkgs.python3
    pkgs.swig
    pkgs.xxd
    pkgs.coreutils
    pkgs.findutils
    pkgs.gnused
    pkgs.gawk
    pkgs.gnugrep
  ];
in
{
  inherit ubootToolchain;

  packages = {
    inherit find-sheng exec mk-boot-img;

    read-blackbox = mkPython "read-blackbox" [ exec ];
    capture-linux-dpu = mkPython "capture-linux-dpu" [ exec ];

    uboot = mk "uboot" (ubootToolchain ++ [ mk-boot-img ]);

    refs = mk "refs" [
      pkgs.git
      pkgs.coreutils
      pkgs.gnugrep
    ];

    soak = mk "soak" [
      pkgs.openssh
      pkgs.coreutils
      find-sheng
    ];

    sheng-mdss-status = mk "sheng-mdss-status" [
      pkgs.openssh
      pkgs.coreutils
      find-sheng
    ];

    builder = mk "builder" [
      pkgs.coreutils
      pkgs.git
    ];

    flash-uboot = mk "flash-uboot" [
      pkgs.openssh
      pkgs.coreutils
      find-sheng
    ];

    flash-rootfs = mk "flash-rootfs" [
      pkgs.android-tools
      pkgs.coreutils
    ];

    fastboot-flash = mk "fastboot-flash" [
      pkgs.android-tools
      pkgs.coreutils
      pkgs.gnugrep
    ];
  };
}
