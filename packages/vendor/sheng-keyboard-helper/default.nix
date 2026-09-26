# Restores fold-angle behavior for the detachable keyboard cover (disables
# keyboard/touchpad when folded back) and syncs the mic-mute LED with the
# active PipeWire session. Ships its own units and udev rules, which start it.
# Source: https://github.com/ianchb/xiaomi-sheng-keyboard-helper
{
  lib,
  stdenv,
  fetchFromGitHub,
  pkg-config,
  coreutils,
  glib,
  libssc,
}:

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
  buildInputs = [
    glib
    libssc
  ];

  # The Makefile hardcodes the libssc include dir and installs under
  # $(DESTDIR)/usr. -Werror is too strict for compilers this new.
  postPatch = ''
    substituteInPlace Makefile \
      --replace-fail -Werror "" \
      --replace-fail /usr/include/libssc ${lib.getDev libssc}/include/libssc \
      --replace-fail '$(DESTDIR)/usr' '$(DESTDIR)'
    substituteInPlace systemd/*.service systemd-user/*.service \
      --replace-fail /usr/libexec "$out/libexec"
    substituteInPlace udev/*.rules \
      --replace-fail /usr/bin/chmod ${lib.getExe' coreutils "chmod"}
  '';

  installFlags = [ "DESTDIR=${placeholder "out"}" ];

  meta = {
    description = "Fold-angle and mic-mute helper for the sheng keyboard accessory";
    license = lib.licenses.asl20;
    platforms = [ "aarch64-linux" ];
  };
}
