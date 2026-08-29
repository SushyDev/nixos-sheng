# Xiaomi MiPPS charger authentication daemon. No source exists for this
# anywhere -- upstream ships only a prebuilt ELF, as postmarketOS does too.
{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  autoPatchelfHook,
  makeWrapper,
  glib,
  util-linux,
  python3,
}:

stdenvNoCC.mkDerivation {
  pname = "sheng-mipps-auth";
  version = "0.21";

  src = fetchFromGitHub {
    owner = "ianchb";
    repo = "xiaomi-mipps-auth";
    rev = "9176efbdf276b874fc0a97912a914449a88155fb";
    hash = "sha256-4zsTGlkTrL5w1TYeCKr3jTWYTQdHza0qcmdVJGQvZ5A=";
  };

  nativeBuildInputs = [
    autoPatchelfHook
    makeWrapper
  ];
  buildInputs = [ glib ];

  dontBuild = true;
  dontConfigure = true;

  installPhase = ''
    runHook preInstall

    # Despite the naming convention, this one is a python script, so
    # autoPatchelfHook does nothing for it. Wrapped rather than shebang-
    # patched, since /usr/bin/env is an FHS path either way.
    install -Dm755 xiaomi-mipps-auth "$out/libexec/xiaomi-mipps-auth"
    wrapProgram "$out/libexec/xiaomi-mipps-auth" \
      --prefix PATH : "${python3}/bin:${lib.getBin glib}/bin"
    install -Dm644 xiaomi-mipps-auth.service \
      "$out/lib/systemd/system/xiaomi-mipps-auth.service"
    install -Dm644 90-xiaomi-mipps-auth.rules \
      "$out/lib/udev/rules.d/90-xiaomi-mipps-auth.rules"

    substituteInPlace "$out/lib/systemd/system/xiaomi-mipps-auth.service" \
      --replace-quiet "/usr/libexec/xiaomi-mipps-auth" "$out/libexec/xiaomi-mipps-auth" \
      --replace-quiet "/usr/bin/flock" "${util-linux}/bin/flock"
    substituteInPlace "$out/lib/udev/rules.d/90-xiaomi-mipps-auth.rules" \
      --replace-quiet "/usr/libexec/xiaomi-mipps-auth" "$out/libexec/xiaomi-mipps-auth"

    runHook postInstall
  '';

  meta = {
    description = "Xiaomi MiPPS charger authentication daemon (prebuilt, no source available)";
    license = lib.licenses.unfree;
    platforms = [ "aarch64-linux" ];
  };
}
