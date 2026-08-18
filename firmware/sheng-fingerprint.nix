# FPC1553 fingerprint sensor support via a patched libfprint + fprintd,
# backed by Qualcomm's QTEE (TrustZone) runtime.
#
# Hybrid package: the backend glue (backend/src/*.c) and libfprint/fprintd
# patches are real source, but the QTEE listener libraries and
# qteesupplicant binary under prebuilt/aarch64/ are proprietary,
# aarch64-only blobs (Qualcomm's closed TEE runtime) that cannot be
# rebuilt from source -- this package will always carry that binary
# component. It also provides qteesupplicant.service, which
# sheng-devauth.service depends on.
#
# Source: https://github.com/ianchb/xiaomi-sheng-fingerprint
{ lib
, stdenv
, fetchFromGitHub
, fetchurl
, meson
, ninja
, pkg-config
, patchelf
, glib
, gusb
, nss
, pixman
}:

let
  libfprintVersion = "1.94.10";

  libfprintSrc = fetchurl {
    url = "https://deb.debian.org/debian/pool/main/libf/libfprint/libfprint_${libfprintVersion}.orig.tar.xz";
    hash = "sha256-/1gnCL54RJgrp221c2rs3kqygThfu1W5mvX3S7FIS1I=";
  };
in
stdenv.mkDerivation {
  pname = "sheng-fingerprint";
  version = "0.1.4";

  src = fetchFromGitHub {
    owner = "ianchb";
    repo = "xiaomi-sheng-fingerprint";
    rev = "76e7301163b0e708f609c9864b3e5833e9f57402";
    hash = "sha256-EgP2w+60JpeTrHJf0AKN9Vmo/SdEpKXtv/j4mtkwmF4=";
  };

  nativeBuildInputs = [ meson ninja pkg-config patchelf ];
  buildInputs = [ glib gusb nss pixman ];

  LIBFPRINT_TARBALL = libfprintSrc;

  # The top-level repo isn't itself a meson project -- scripts/build-*.sh
  # invoke meson internally for the vendored libfprint copy -- so skip
  # stdenv's automatic mesonConfigurePhase (would run against the repo
  # root, which has no meson.build, and fail).
  dontConfigure = true;

  # Verify the checked-in prebuilt QTEE blobs against the repo's own
  # checksums before using them.
  postPatch = ''
    sha256sum -c prebuilt/aarch64/SHA256SUMS
  '';

  buildPhase = ''
    runHook preBuild

    scripts/build-backend.sh build/native/backend
    scripts/build-libfprint.sh build/native/backend build/native/libfprint

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    nativeDir=build/native
    fpDir="$out/lib/xiaomi-sheng-fingerprint"
    listenerDir="$out/lib/qtee-listeners"

    install -d -m 0755 "$fpDir" "$listenerDir" "$out/libexec" \
      "$out/lib/systemd/system/fprintd.service.d" "$out/lib/udev/rules.d"

    install -m 0644 "$nativeDir/libfprint/libfprint-2.so.2.0.0" "$fpDir/"
    install -m 0644 "$nativeDir/backend/libfpc1553-qtee.so" "$fpDir/"
    ln -s libfprint-2.so.2.0.0 "$fpDir/libfprint-2.so.2"
    ln -s libfprint-2.so.2 "$fpDir/libfprint-2.so"

    install -m 0755 prebuilt/aarch64/qteesupplicant "$out/libexec/"
    install -m 0755 prebuilt/aarch64/sfs_config "$out/libexec/fpc-sfs-config"

    for listener in prebuilt/aarch64/qtee-listeners/*.so.1.0.0; do
      name=$(basename "$listener")
      install -m 0644 "$listener" "$listenerDir/$name"
      ln -s "$name" "$listenerDir/''${name%.0.0}"
    done

    substitute systemd/qteesupplicant.service "$out/lib/systemd/system/qteesupplicant.service" \
      --replace-fail /usr/libexec "$out/libexec" \
      --replace-fail /usr/lib/aarch64-linux-gnu/qtee-listeners "$listenerDir"
    install -m 0644 systemd/sfsconfig.service "$out/lib/systemd/system/"
    substitute systemd/sfsconfig.service "$out/lib/systemd/system/sfsconfig.service" \
      --replace-fail /usr/libexec "$out/libexec"
    substitute systemd/fprintd.service.d/10-xiaomi-sheng-fpc1553.conf \
      "$out/lib/systemd/system/fprintd.service.d/10-xiaomi-sheng-fpc1553.conf" \
      --replace-fail /usr/lib/xiaomi-sheng-fingerprint "$fpDir"
    install -m 0644 udev/99-qcomtee-fpc.rules "$out/lib/udev/rules.d/"

    runHook postInstall
  '';

  meta = {
    description = "FPC1553 fingerprint sensor support for the sheng board (Apache-2.0 glue + LGPL/GPL patches; QTEE runtime blobs unfree)";
    license = with lib.licenses; [ asl20 lgpl21Plus gpl2Plus bsd3 ];
    platforms = [ "aarch64-linux" ];
  };
}
