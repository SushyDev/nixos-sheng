# Userspace client library for Qualcomm's Sensor Core (SSC) DSP stack --
# talks QMI/QRTR to the sensorspd daemon running on the aDSP.
# Source: https://codeberg.org/DylanVanAssche/libssc
{
  lib,
  stdenv,
  fetchFromGitea,
  meson,
  ninja,
  pkg-config,
  glib,
  protobuf,
  protobufc,
  libqmi,
}:

stdenv.mkDerivation {
  pname = "libssc";
  version = "0.3.0";

  src = fetchFromGitea {
    domain = "codeberg.org";
    owner = "DylanVanAssche";
    repo = "libssc";
    rev = "f6dfbfa5f34ef22f3d47ef346c22834e79c60df1"; # main as of 2026-08-18
    hash = "sha256-UPLKuePBKgQsA0qgY5xcvoj6jpxHhxJ9pMWJdD23LSg=";
  };

  # Retries the SSC service lookup, because sensorspd takes a moment to
  # enumerate on QRTR after adsprpcd-sensorspd.service starts. Replaces
  # debian-sheng's wait_for_qmi_service.patch, whose retry loop had no early
  # exit and so cost a flat 5s per SSC client -- 20s across the four sensors
  # iio-sensor-proxy opens.
  patches = [ ./0100-retry-the-ssc-lookup-without-a-fixed-delay.patch ];

  nativeBuildInputs = [
    meson
    ninja
    pkg-config
    protobuf
  ];
  buildInputs = [ glib ];
  # libssc.pc Requires: these, so consumers resolving it via pkg-config need
  # them on their own PKG_CONFIG_PATH.
  propagatedBuildInputs = [
    protobufc
    libqmi
  ];

  meta = {
    description = "Client library for Qualcomm Sensor Core (SSC)";
    license = lib.licenses.gpl3Only; # upstream ships a bare GPLv3 text, no "or later" grant
    platforms = [ "aarch64-linux" ];
  };
}
