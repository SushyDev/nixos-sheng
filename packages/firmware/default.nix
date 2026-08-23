# Entrypoint: aggregates every sheng vendor userspace package into one
# attrset, callPackage-style. Consumed by nixos/xiaomi-sheng-services.nix.
{ lib, callPackage }:

let
  libssc = callPackage ./libssc.nix { };
in
{
  inherit libssc;

  sheng-firmware-blobs = callPackage ./sheng-firmware-blobs.nix { };
  fastrpc = callPackage ./fastrpc.nix { };
  iio-sensor-proxy = callPackage ./iio-sensor-proxy.nix { inherit libssc; };
  sheng-sensors = callPackage ./sheng-sensors.nix { };
  sheng-devauth = callPackage ./sheng-devauth.nix { };
  alsa-ucm-sheng = callPackage ./alsa-ucm-sheng.nix { };
  sheng-fingerprint = callPackage ./sheng-fingerprint.nix { };
  sheng-thp = callPackage ./sheng-thp.nix { inherit libssc; };
  sheng-pen-status = callPackage ./sheng-pen-status.nix { };
  sheng-keyboard-helper = callPackage ./sheng-keyboard-helper.nix { inherit libssc; };
  sheng-mipps-auth = callPackage ./sheng-mipps-auth.nix { };
  sheng-charger-mode = callPackage ./sheng-charger-mode.nix { };
}
