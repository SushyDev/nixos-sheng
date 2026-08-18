# Xiaomi MiPPS charger authentication daemon.
#
# NOTE: no source code exists anywhere for this component -- the upstream
# repo contains only a checked-in prebuilt ELF binary and packaging
# scripts (confirmed both directly and via postmarketOS's own APKBUILD,
# which likewise just repackages this same binary with a no-op build()).
# Vendored as-is; cannot be built from source.
{ lib, stdenvNoCC, fetchFromGitHub, autoPatchelfHook, glib }:

stdenvNoCC.mkDerivation {
  pname = "sheng-mipps-auth";
  version = "0.21";

  src = fetchFromGitHub {
    owner = "ianchb";
    repo = "xiaomi-mipps-auth";
    rev = "9176efbdf276b874fc0a97912a914449a88155fb";
    hash = "sha256-4zsTGlkTrL5w1TYeCKr3jTWYTQdHza0qcmdVJGQvZ5A=";
  };

  nativeBuildInputs = [ autoPatchelfHook ];
  buildInputs = [ glib ];

  dontBuild = true;
  dontConfigure = true;

  installPhase = ''
    runHook preInstall

    install -Dm755 xiaomi-mipps-auth "$out/libexec/xiaomi-mipps-auth"
    install -Dm644 xiaomi-mipps-auth.service \
      "$out/lib/systemd/system/xiaomi-mipps-auth.service"
    install -Dm644 90-xiaomi-mipps-auth.rules \
      "$out/lib/udev/rules.d/90-xiaomi-mipps-auth.rules"

    # Upstream's unit/udev rule hardcode the FHS path /usr/libexec/...;
    # point them at the actual Nix store path instead.
    substituteInPlace "$out/lib/systemd/system/xiaomi-mipps-auth.service" \
      --replace-quiet "/usr/libexec/xiaomi-mipps-auth" "$out/libexec/xiaomi-mipps-auth"
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
