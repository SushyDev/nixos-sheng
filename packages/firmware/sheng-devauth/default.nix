# Keyboard authentication daemon, paired with a kernel driver to
# authenticate the Xiaomi detachable keyboard accessory.
# Source: https://github.com/ianchb/sheng_devauth
{
  lib,
  stdenv,
  fetchFromGitHub,
}:

stdenv.mkDerivation {
  pname = "sheng-devauth";
  version = "1.0";

  src = fetchFromGitHub {
    owner = "ianchb";
    repo = "sheng_devauth";
    rev = "bac03b5bcfefa1467ebad490edd910a6cef8a207";
    hash = "sha256-iLGMnlYJV3F4IhNUaSzsTqa1Wp5rHswxk7AuXof9HzA=";
  };

  # main.c hardcodes an FHS firmware directory, looked up directly rather than
  # through the kernel firmware API. /run/current-system/firmware is already
  # the flattened root, so there is no lib/firmware/ segment to keep.
  postPatch = ''
    substituteInPlace main.c \
      --replace-fail "/usr/lib/firmware/qcom/sm8550/sheng" \
                      "/run/current-system/firmware/qcom/sm8550/sheng"
  '';

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
