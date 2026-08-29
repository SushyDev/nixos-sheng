# NT36532E userspace touch host processor: reads raw THP frames from the
# kernel driver and exposes multitouch + Focus Pen stylus via uinput.
# Source: https://github.com/ianchb/xiaomi-sheng-thp
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
  pname = "sheng-thp";
  version = "0.3.9";

  src = fetchFromGitHub {
    owner = "ianchb";
    repo = "xiaomi-sheng-thp";
    rev = "34046210932d654a4c0df0121ecc31c008f8148c";
    hash = "sha256-+eSthfDjeP4nueqDuR88ZuWsWFs/4yxMH6iSlnujJpA=";
  };

  nativeBuildInputs = [ pkg-config ];
  buildInputs = [
    glib
    libssc
  ];

  # Upstream's Makefile hardcodes -I/usr/include/libssc instead of using
  # pkg-config. -Werror is too strict for compilers this new.
  postPatch = ''
    substituteInPlace Makefile \
      --replace-fail -Werror "" \
      --replace-fail "/usr/include/libssc" "${libssc}/include/libssc"
  '';

  installFlags = [
    "PREFIX=${placeholder "out"}"
    "DESTDIR="
  ];

  postInstall = ''
    substituteInPlace "$out/lib/systemd/system/xiaomi-sheng-thp.service" \
      --replace-fail "/usr/bin/test" "${coreutils}/bin/test" \
      --replace-fail "/usr/libexec/xiaomi-sheng-thp" "$out/libexec/xiaomi-sheng-thp"
  '';

  meta = {
    description = "NT36532E userspace touch host processor for sheng";
    license = lib.licenses.asl20;
    platforms = [ "aarch64-linux" ];
  };
}
