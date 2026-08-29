# Framebuffer charger-mode screen, shown when the cmdline carries
# androidboot.mode=charger. Prebuilt ELF; no source exists.
{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  autoPatchelfHook,
}:

stdenvNoCC.mkDerivation {
  pname = "sheng-charger-mode";
  version = "0.1";

  src = fetchFromGitHub {
    owner = "ianchb";
    repo = "xiaomi-charger-mode";
    rev = "0c00fcd2cb064f563f44babb345c1dffecf2ada2"; # master as of 2026-08-18
    hash = "sha256-g0IfrZzQ98Uwd2kXEZeYt9Zwf0dzTw12nyoDMgL69WQ=";
  };

  nativeBuildInputs = [ autoPatchelfHook ];

  dontBuild = true;
  dontConfigure = true;

  installPhase = ''
    runHook preInstall

    install -Dm755 xiaomi-charger-mode "$out/libexec/xiaomi-charger-mode"
    install -Dm644 xiaomi-charger-mode.service \
      "$out/lib/systemd/system/xiaomi-charger-mode.service"

    runHook postInstall
  '';

  meta = {
    description = "Xiaomi charger-mode UI daemon (prebuilt, no source available)";
    license = lib.licenses.unfree;
    platforms = [ "aarch64-linux" ];
  };
}
