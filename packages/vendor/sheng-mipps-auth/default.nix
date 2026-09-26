# Xiaomi MiPPS charger authentication, without which the charger negotiates
# down from 120 W. Source: https://github.com/ianchb/xiaomi-mipps-auth
{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  makeWrapper,
  python3,
  glib,
  systemd,
  util-linux,
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

  nativeBuildInputs = [ makeWrapper ];
  # For patchShebangs.
  buildInputs = [ python3 ];

  postPatch = ''
    substituteInPlace xiaomi-mipps-auth.service \
      --replace-fail /usr/bin/flock ${lib.getExe' util-linux "flock"} \
      --replace-fail /usr/libexec "$out/libexec"
    substituteInPlace 90-xiaomi-mipps-auth.rules \
      --replace-fail /usr/libexec "$out/libexec"
  '';

  installPhase = ''
    runHook preInstall

    install -Dm755 -t "$out/libexec" xiaomi-mipps-auth
    install -Dm644 -t "$out/lib/systemd/system" xiaomi-mipps-auth.service
    install -Dm644 -t "$out/lib/udev/rules.d" 90-xiaomi-mipps-auth.rules

    runHook postInstall
  '';

  # It shells out to gdbus for the desktop notification and to systemctl
  # when run from the udev rule, where PATH is minimal.
  postFixup = ''
    wrapProgram "$out/libexec/xiaomi-mipps-auth" \
      --prefix PATH : ${
        lib.makeBinPath [
          glib
          systemd
        ]
      }
  '';

  meta = {
    description = "Xiaomi MiPPS charger authentication";
    license = lib.licenses.gpl2Only;
    platforms = [ "aarch64-linux" ];
  };
}
