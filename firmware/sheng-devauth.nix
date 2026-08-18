# Keyboard authentication daemon, paired with a kernel driver to
# authenticate the Xiaomi detachable keyboard accessory.
# Source: https://github.com/ianchb/sheng_devauth
{ lib, stdenv, fetchFromGitHub }:

stdenv.mkDerivation {
  pname = "sheng-devauth";
  version = "1.0";

  src = fetchFromGitHub {
    owner = "ianchb";
    repo = "sheng_devauth";
    rev = "bac03b5bcfefa1467ebad490edd910a6cef8a207";
    hash = "sha256-iLGMnlYJV3F4IhNUaSzsTqa1Wp5rHswxk7AuXof9HzA=";
  };

  installPhase = ''
    runHook preInstall

    install -Dm755 xiaomi_devauth "$out/bin/xiaomi_devauth"
    install -Dm644 ${./sheng-devauth.service} \
      "$out/lib/systemd/system/sheng-devauth.service"

    runHook postInstall
  '';

  meta = {
    description = "Xiaomi keyboard-accessory authentication daemon";
    license = lib.licenses.bsd3;
    platforms = [ "aarch64-linux" ];
  };
}
