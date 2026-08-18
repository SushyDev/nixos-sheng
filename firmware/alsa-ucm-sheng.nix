# ALSA UCM2 profile for the sheng board's WCD938X audio codec.
{ lib, stdenvNoCC, fetchurl }:

stdenvNoCC.mkDerivation {
  pname = "alsa-ucm-sheng";
  version = "unstable";

  dontUnpack = true;

  hifiConf = fetchurl {
    url = "https://gitlab.postmarketos.org/alghiffaryfa19/pmaports/-/raw/sheng/device/testing/device-xiaomi-sheng/HiFi.conf";
    hash = "sha256-j55P9r5QEmBiK7Ecg3ykshcQEOw+Ua6YkvWnGGzl3YE=";
  };

  installPhase = ''
    runHook preInstall

    install -Dm644 "$hifiConf" \
      "$out/share/alsa/ucm2/Xiaomi/sheng/HiFi.conf"
    install -Dm644 ${./Xiaomi-Pad6SPro.conf} \
      "$out/share/alsa/ucm2/Xiaomi/sheng/Xiaomi-Pad6SPro.conf"

    mkdir -p "$out/share/alsa/ucm2/conf.d/sm8550"
    ln -s ../../Xiaomi/sheng/Xiaomi-Pad6SPro.conf \
      "$out/share/alsa/ucm2/conf.d/sm8550/Xiaomi-Pad6SPro.conf"

    runHook postInstall
  '';

  meta = {
    description = "ALSA UCM2 profile for the sheng board (WCD938X codec)";
    license = lib.licenses.mit;
    platforms = [ "aarch64-linux" ];
  };
}
