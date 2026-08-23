# Qt tray utility + CLI showing Focus Pen stylus battery/pairing status via
# qcom_battmgr sysfs, auto-pairs the stylus over BlueZ.
# Source: https://github.com/ianchb/xiaomi-pen-status
{ lib, stdenv, fetchFromGitHub, qt6, pkg-config }:

stdenv.mkDerivation {
  pname = "sheng-pen-status";
  version = "0.2.3";

  src = fetchFromGitHub {
    owner = "ianchb";
    repo = "xiaomi-pen-status";
    rev = "8b0ff3eb143b84541cc1e55ea9cdd3a723256021";
    hash = "sha256-qQ/9y/CsJN3E1EIUbAJx4iMF8SQ+hMokYJrVCgYG7bA=";
  };

  nativeBuildInputs = [ qt6.qmake qt6.wrapQtAppsHook pkg-config ];
  buildInputs = [ qt6.qtbase qt6.qtsvg ];

  buildPhase = ''
    runHook preBuild

    qmake6 xiaomi-pen-status.pro
    make

    $CXX -std=c++17 -O2 -Wall -Wextra -pedantic \
      xiaomi-pen-status-cli.cpp -o xiaomi-pen-status-cli

    runHook postBuild
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
