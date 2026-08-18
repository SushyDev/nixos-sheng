# Userspace client library for Qualcomm's Sensor Core (SSC) DSP stack --
# talks QMI/QRTR to the sensorspd daemon running on the aDSP.
# Source: https://codeberg.org/DylanVanAssche/libssc
{ lib
, stdenv
, fetchFromGitea
, fetchpatch
, meson
, ninja
, pkg-config
, glib
, protobuf
, protobufc
, libqmi
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

  # Adds a 5x1s retry loop around the SSC QRTR/QMI service lookup, since
  # sensorspd can take a moment to enumerate on QRTR after
  # adsprpcd-sensorspd.service starts. Fetched from the reference
  # packaging rather than vendored, since we never inspected the literal
  # diff content.
  patches = [
    (fetchpatch {
      url = "https://raw.githubusercontent.com/ianchb/debian-sheng/master/patches/wait_for_qmi_service.patch";
      hash = "sha256-Ee3Jq8ITM5WQebHaYWZeVTuPYBFu3uMbDIoSQ3Zb6Cg=";
    })
  ];

  nativeBuildInputs = [ meson ninja pkg-config protobuf ];
  buildInputs = [ glib ];
  # libssc.pc's Requires: pulls in qmi-glib/protobuf-c -- propagate so
  # downstream consumers (iio-sensor-proxy, sheng-thp, ...) resolving
  # libssc via pkg-config also get these on their own PKG_CONFIG_PATH.
  propagatedBuildInputs = [ protobufc libqmi ];

  meta = {
    description = "Client library for Qualcomm Sensor Core (SSC)";
    license = lib.licenses.gpl3Plus;
    platforms = [ "aarch64-linux" ];
  };
}
