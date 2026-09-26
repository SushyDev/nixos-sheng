# Qualcomm FastRPC userspace: the DSP RPC transport and the *rpcd daemons.
# Source: https://github.com/qualcomm/fastrpc
{
  lib,
  stdenv,
  fetchFromGitHub,
  autoreconfHook,
  pkg-config,
  libyaml,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "fastrpc";
  version = "1.0.2";

  src = fetchFromGitHub {
    owner = "qualcomm";
    repo = "fastrpc";
    tag = "v${finalAttrs.version}";
    hash = "sha256-/RXH34zqAxtWty75UHoOvS6fdmB+UfTRtB6G9IZiSWk=";
  };

  nativeBuildInputs = [
    autoreconfHook
    pkg-config
  ];
  buildInputs = [ libyaml ];

  # Upstream's default is /usr/share/qcom, which nothing on NixOS populates; an
  # empty DSP search path makes the aDSP's sns_registry abort the whole ADSP.
  configureFlags = [ "--with-config-base-dir=/var/lib/qcom" ];

  postInstall = ''
    rm -r "$out"/{bin,lib,share}/fastrpc_test
  '';

  # Each daemon dlopens its lib*_default_listener.so rather than linking it, so
  # nothing puts $out/lib on its RUNPATH. Without it adsprpcd restart-loops and
  # the sensor PD never loads, which surfaces only as missing sensors.
  postFixup = ''
    for daemon in "$out"/bin/*rpcd; do
      patchelf --add-rpath "$out/lib" "$daemon"
    done
  '';

  meta = {
    description = "Qualcomm FastRPC userspace and DSP RPC daemons";
    homepage = "https://github.com/qualcomm/fastrpc";
    license = lib.licenses.bsd3;
    platforms = [ "aarch64-linux" ];
  };
})
