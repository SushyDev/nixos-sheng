# Restores fold-angle behavior for the detachable keyboard cover (disables
# keyboard/touchpad when folded back) and syncs the mic-mute LED with the
# active PipeWire session.
# Source: https://github.com/ianchb/xiaomi-sheng-keyboard-helper
{ lib, stdenv, fetchFromGitHub, pkg-config, glib, libssc }:

stdenv.mkDerivation {
  pname = "sheng-keyboard-helper";
  version = "0.2.0";

  src = fetchFromGitHub {
    owner = "ianchb";
    repo = "xiaomi-sheng-keyboard-helper";
    rev = "3bb9aada8814e81a5c22de5d1e5dd70f4b99183e";
    hash = "sha256-02sEMWSmyRxr5mf+0Ie6iqVD8tTOCiRVKVrC8xvN4xg=";
  };

  nativeBuildInputs = [ pkg-config ];
  buildInputs = [ glib libssc ];

  # Upstream's Makefile hardcodes -I/usr/include/libssc (assumes an FHS
  # system-wide install) instead of using pkg-config; point it at the
  # actual Nix store path. Also drops -Werror, too strict against newer
  # compilers than this was written against.
  postPatch = ''
    substituteInPlace Makefile \
      --replace-fail -Werror "" \
      --replace-fail "/usr/include/libssc" "${libssc}/include/libssc"
  '';

  installFlags = [ "DESTDIR=${placeholder "out"}" ];

  postInstall = ''
    mv "$out/usr"/* "$out/"
    rmdir "$out/usr"
  '';

  meta = {
    description = "Fold-angle + mic-mute helper for the sheng keyboard accessory";
    license = lib.licenses.asl20;
    platforms = [ "aarch64-linux" ];
  };
}
