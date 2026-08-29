# Qualcomm SSC registry blobs for the board's sensors, plus the udev rule that
# tags fastrpc-adsp so iio-sensor-proxy's SSC backend recognizes it.
# Source: https://github.com/alghiffaryfa19/sheng-sensors-file
{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
}:

stdenvNoCC.mkDerivation {
  pname = "sheng-sensors";
  version = "20240917";

  src = fetchFromGitHub {
    owner = "alghiffaryfa19";
    repo = "sheng-sensors-file";
    rev = "199754bb37ae6d4706bd8d4b23e9e6fec2d959cc";
    hash = "sha256-yXX8QUxQ45yS0zCkpXQneiOhinOVCZrjNJVc824dHqQ=";
  };

  dontBuild = true;
  dontConfigure = true;

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/share"
    cp -r --no-preserve=mode -- usr/share/qcom "$out/share/"

    install -Dm644 ${./81-sheng-ssc-sensors.rules} \
      "$out/lib/udev/rules.d/81-sheng-ssc-sensors.rules"

    runHook postInstall
  '';

  meta = {
    description = "Qualcomm SSC sensor registry/config data for the sheng board";
    license = lib.licenses.unfree;
    platforms = [ "aarch64-linux" ];
  };
}
