# Flat mirror of /lib/firmware for the sheng board.
# Source: https://github.com/ianchb/sheng-firmware (branch: master)
#
# This repo ships no LICENSE file, so redistribution terms are undefined.
# Flag before publishing.
{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
}:

stdenvNoCC.mkDerivation {
  pname = "sheng-firmware-blobs";
  version = "unstable";

  src = fetchFromGitHub {
    owner = "ianchb";
    repo = "sheng-firmware";
    rev = "2c1e2729a085c7f0470c855d236e49455c4601f0"; # master as of 2026-08-18
    hash = "sha256-8aoSMGso93KQKtMgo7CwI0AdMdHrdmY9aLRd/Ywm/0E=";
  };

  dontBuild = true;
  dontConfigure = true;

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/lib/firmware"
    cp -r --no-preserve=mode -- . "$out/lib/firmware/"
    runHook postInstall
  '';

  meta = {
    description = "Firmware blobs for the Xiaomi Pad 6S Pro (sheng)";
    license = lib.licenses.unfree;
    platforms = [ "aarch64-linux" ];
  };
}
