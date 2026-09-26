# ALSA UCM2 profile for the sheng board, in alsa-ucm-conf's layout: the card
# config under conf.d/<driver>/, pointing at the verb file beside it.
{
  lib,
  stdenvNoCC,
  fetchurl,
}:

let
  # postmarketOS device port by alghiffaryfa19, `sheng` branch.
  pmaportsRev = "2c3115ea6bc209013c3b184c155552141805468d";
in
stdenvNoCC.mkDerivation {
  pname = "alsa-ucm-sheng";
  version = "0-unstable-2026-08-01";

  src = fetchurl {
    url = "https://gitlab.postmarketos.org/alghiffaryfa19/pmaports/-/raw/${pmaportsRev}/device/testing/device-xiaomi-sheng/HiFi.conf";
    hash = "sha256-j55P9r5QEmBiK7Ecg3ykshcQEOw+Ua6YkvWnGGzl3YE=";
  };

  dontUnpack = true;

  installPhase = ''
    runHook preInstall

    dir="$out/share/alsa/ucm2"
    install -Dm644 "$src" "$dir/Xiaomi/sheng/HiFi.conf"
    install -Dm644 ${./Xiaomi-Pad6SPro.conf} "$dir/Xiaomi/sheng/Xiaomi-Pad6SPro.conf"
    mkdir -p "$dir/conf.d/sm8550"
    ln -s ../../Xiaomi/sheng/Xiaomi-Pad6SPro.conf "$dir/conf.d/sm8550/Xiaomi-Pad6SPro.conf"

    runHook postInstall
  '';

  meta = {
    description = "ALSA UCM2 profile for the Xiaomi Pad 6S Pro (sheng)";
    license = lib.licenses.mit; # the device APKBUILD's
    platforms = [ "aarch64-linux" ];
  };
}
