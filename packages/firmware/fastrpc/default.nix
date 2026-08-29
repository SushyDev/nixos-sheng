# Qualcomm FastRPC userspace (ADSP RPC transport) + the adsprpcd sensor
# daemon service. Source: https://github.com/qualcomm/fastrpc (v1.0.2).
{
  lib,
  stdenv,
  fetchFromGitHub,
  autoreconfHook,
  pkg-config,
  patchelf,
  libyaml,
}:

stdenv.mkDerivation rec {
  pname = "fastrpc";
  version = "1.0.2";

  src = fetchFromGitHub {
    owner = "qualcomm";
    repo = "fastrpc";
    rev = "v${version}";
    hash = "sha256-/RXH34zqAxtWty75UHoOvS6fdmB+UfTRtB6G9IZiSWk=";
  };

  nativeBuildInputs = [
    autoreconfHook
    pkg-config
    patchelf
  ];
  buildInputs = [ libyaml ];

  postInstall = ''
    install -Dm755 src/adsprpcd "$out/bin/adsprpcd"
    rm -rf "$out/share/fastrpc_test" "$out/bin/fastrpc_test"

    install -Dm644 ${./adsprpcd-sensorspd.service} \
      "$out/lib/systemd/system/adsprpcd-sensorspd.service"
  '';

  # postInstall copies adsprpcd straight out of the build tree, bypassing
  # libtool's install step, so it carries an RPATH of glibc only and never
  # dlopens libadsp_default_listener.so.1. It then restart-loops forever and
  # the sensor PD never loads, which surfaces only as missing sensors.
  postFixup = ''
    patchelf --add-rpath "$out/lib" "$out/bin/adsprpcd"
    patchelf --add-rpath "$out/lib" "$out/bin/cdsprpcd"
  '';

  meta = {
    description = "Qualcomm FastRPC userspace + ADSP sensor RPC daemon";
    license = lib.licenses.bsd3;
    platforms = [ "aarch64-linux" ];
  };
}
