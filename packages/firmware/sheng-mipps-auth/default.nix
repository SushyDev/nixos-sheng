# Xiaomi MiPPS charger authentication daemon.
#
# NOTE: no source code exists anywhere for this component -- the upstream
# repo contains only a checked-in prebuilt ELF binary and packaging
# scripts (confirmed both directly and via postmarketOS's own APKBUILD,
# which likewise just repackages this same binary with a no-op build()).
# Vendored as-is; cannot be built from source.
{ lib, stdenvNoCC, fetchFromGitHub, autoPatchelfHook, makeWrapper, glib, util-linux, python3 }:

stdenvNoCC.mkDerivation {
  pname = "sheng-mipps-auth";
  version = "0.21";

  src = fetchFromGitHub {
    owner = "ianchb";
    repo = "xiaomi-mipps-auth";
    rev = "9176efbdf276b874fc0a97912a914449a88155fb";
    hash = "sha256-4zsTGlkTrL5w1TYeCKr3jTWYTQdHza0qcmdVJGQvZ5A=";
  };

  nativeBuildInputs = [ autoPatchelfHook makeWrapper ];
  buildInputs = [ glib ];

  dontBuild = true;
  dontConfigure = true;

  installPhase = ''
    runHook preInstall

    # "xiaomi-mipps-auth" is actually a #!/usr/bin/env python3 script, not
    # the prebuilt ELF blob the rest of this package's naming convention
    # suggests (confirmed on hardware: "env: 'python3': No such file or
    # directory", exit 127 -- autoPatchelfHook, being for ELF binaries,
    # did nothing for it). Wrap it so python3 is on PATH instead of
    # patching the shebang, since /usr/bin/env itself is also an FHS path
    # that substituteInPlace would just move the problem to.
    install -Dm755 xiaomi-mipps-auth "$out/libexec/xiaomi-mipps-auth"
    wrapProgram "$out/libexec/xiaomi-mipps-auth" \
      --prefix PATH : "${python3}/bin"
    install -Dm644 xiaomi-mipps-auth.service \
      "$out/lib/systemd/system/xiaomi-mipps-auth.service"
    install -Dm644 90-xiaomi-mipps-auth.rules \
      "$out/lib/udev/rules.d/90-xiaomi-mipps-auth.rules"

    # Upstream's unit/udev rule hardcode the FHS paths /usr/libexec/... and
    # /usr/bin/flock; point them at the actual Nix store paths instead.
    # (/usr/bin/flock confirmed on hardware: service failed with "Unable
    # to locate executable '/usr/bin/flock'", exit 203/EXEC.)
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
