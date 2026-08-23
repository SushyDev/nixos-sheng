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

  # main.c hardcodes /usr/lib/firmware/qcom/sm8550/sheng (an FHS path that
  # doesn't exist on NixOS) as the TZ app's firmware directory, looked up
  # directly rather than through the kernel firmware API (confirmed on
  # hardware: "File /usr/lib/firmware/qcom/sm8550/sheng/devauth.mbn open
  # error: No such file or directory"). /run/current-system/firmware is
  # NixOS's stable, generation-independent firmware search root -- and,
  # unlike the FHS convention, it IS the flattened root already (no nested
  # lib/firmware/ inside it); confirmed on hardware that devauth.mbn
  # actually lands at .../firmware/qcom/sm8550/sheng/devauth.mbn, so a
  # first attempt at this fix that kept the "lib/firmware/" segment still
  # 404'd.
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
