# Qualcomm FastRPC userspace (ADSP RPC transport) + the adsprpcd sensor
# daemon service. Source: https://github.com/qualcomm/fastrpc (v1.0.2).
{ lib
, stdenv
, fetchFromGitHub
, autoreconfHook
, pkg-config
, patchelf
, libyaml
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

  nativeBuildInputs = [ autoreconfHook pkg-config patchelf ];
  buildInputs = [ libyaml ];

  postInstall = ''
    install -Dm755 src/adsprpcd "$out/bin/adsprpcd"
    rm -rf "$out/share/fastrpc_test" "$out/bin/fastrpc_test"

    install -Dm644 ${./adsprpcd-sensorspd.service} \
      "$out/lib/systemd/system/adsprpcd-sensorspd.service"
  '';

  # adsprpcd dlopens libadsp_default_listener.so.1 by bare name, and the
  # binary installed above is copied straight out of the build tree --
  # bypassing libtool's install step -- so it carries an RPATH of glibc
  # only and never finds $out/lib. The daemon then restart-loops:
  #
  #   dsprpcd.c:58: dlopen failed for libadsp_default_listener.so.1
  #   dsprpcd.c:110: ADSP daemon error libadsp_default_listener.so
  #   dsprpcd.c:118: ADSP daemon will restart after 100ms...
  #
  # forever, so the sensor PD never loads. Everything downstream then
  # fails without saying why: ssccli reports "SSC QMI Service not found",
  # iio-sensor-proxy reports HasAccelerometer false, and there is no
  # auto-rotate -- with nothing pointing at a missing RPATH.
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
