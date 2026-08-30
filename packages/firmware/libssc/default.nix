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

  # Retries the SSC service lookup, because sensorspd registers a few seconds
  # after the aDSP boots. Replaces debian-sheng's wait_for_qmi_service.patch,
  # which retried with sleep() inside the main-loop callback and so blocked the
  # very bus it was waiting on.
  # 0101 covers the second race: the aDSP registers its sensors one at a time,
  # so a lookup that now runs early finds accel but not yet ambient light.
  patches = [
    ./0100-retry-the-ssc-lookup-without-blocking-the-main-loop.patch
    ./0101-retry-sensor-discovery-while-the-adsp-registers.patch
  ];

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
