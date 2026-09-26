# Qt tray utility + CLI showing Focus Pen stylus battery/pairing status via
# qcom_battmgr sysfs, auto-pairs the stylus over BlueZ.
# Source: https://github.com/ianchb/xiaomi-pen-status
{
  lib,
  stdenv,
  fetchFromGitHub,
  qt6,
  pkg-config,
}:

stdenv.mkDerivation {
  pname = "sheng-pen-status";
  version = "0.2.3";

  src = fetchFromGitHub {
    owner = "ianchb";
    repo = "xiaomi-pen-status";
    rev = "8b0ff3eb143b84541cc1e55ea9cdd3a723256021";
    hash = "sha256-qQ/9y/CsJN3E1EIUbAJx4iMF8SQ+hMokYJrVCgYG7bA=";
  };

  nativeBuildInputs = [
    qt6.qmake
    qt6.wrapQtAppsHook
    pkg-config
  ];
  buildInputs = [
    qt6.qtbase
    qt6.qtsvg
  ];

  # Upstream commits its Debian build (Makefile, objects, both binaries). With
  # every store mtime equal, make calls those up to date and ships a binary
  # linked against /lib and Qt 6.8.
  postPatch = ''
    rm Makefile main.o qrc_resources.o qrc_resources.cpp \
      xiaomi-pen-status xiaomi-pen-status-cli
  '';

  # The qmake hook configures and builds xiaomi-pen-status.pro; the CLI is a
  # lone source file with no project of its own.
  postBuild = ''
    $CXX -std=c++17 -O2 -Wall -Wextra -pedantic \
      xiaomi-pen-status-cli.cpp -o xiaomi-pen-status-cli
  '';

  installPhase = ''
    runHook preInstall

    install -Dm755 xiaomi-pen-status "$out/bin/xiaomi-pen-status"
    install -Dm755 xiaomi-pen-status-cli "$out/bin/xiaomi-pen-status-cli"
    install -Dm644 xiaomi-pen-status.desktop \
      "$out/share/applications/xiaomi-pen-status.desktop"
    install -Dm644 xiaomi-pen-status.svg \
      "$out/share/icons/hicolor/scalable/apps/xiaomi-pen-status.svg"

    mkdir -p "$out/etc/xdg/autostart"
    sed 's/^Exec=.*/Exec=xiaomi-pen-status/' xiaomi-pen-status.desktop \
      > "$out/etc/xdg/autostart/xiaomi-pen-status.desktop"
    printf 'NotShowIn=GNOME;\n' >> "$out/etc/xdg/autostart/xiaomi-pen-status.desktop"

    runHook postInstall
  '';

  meta = {
    description = "Stylus status tray/CLI for the Xiaomi Focus Pen (sheng)";
    license = lib.licenses.gpl2Only; # upstream ships a bare GPLv2 text, no "or later" grant
    platforms = [ "aarch64-linux" ];
    mainProgram = "xiaomi-pen-status";
  };
}
