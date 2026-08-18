# Upstream iio-sensor-proxy, patched to speak to Qualcomm's SSC sensor
# stack via libssc (accelerometer/proximity/light/compass over QRTR).
# Base: https://gitlab.freedesktop.org/hadess/iio-sensor-proxy (3.8)
# Patches: postmarketOS pmaports !7091 (device/testing/sheng-iio-sensor-proxy)
{ lib
, stdenv
, fetchFromGitLab
, fetchpatch
, meson
, ninja
, pkg-config
, glib
, libgudev
, udev
, polkit
, libssc
}:

let
  pmaportsPatch = name: hash: fetchpatch {
    url = "https://gitlab.postmarketos.org/alghiffaryfa19/pmaports/-/raw/sheng/device/testing/sheng-iio-sensor-proxy/${name}";
    inherit hash;
  };

  # name -> hash, fetched from the fork that actually hosts the `sheng`
  # branch (alghiffaryfa19/pmaports -- postmarketOS/pmaports itself 404s).
  patches_ = [
    [ "0001-WIP-iio-sensor-proxy.c-Do-not-exit-based-on-sensor-e.patch" "sha256-Wjll9MYw3ZyyU+WQq61w1RAram+9ADpIXRbWUWssf7Y=" ]
    [ "0001-iio-sensor-proxy-depend-on-libssc.patch" "sha256-faOpfR6qit68R2b+sk9/k4XeA6Ao5UuerrfFzMaD3MM=" ]
    [ "0002-proximity-support-SSC-proximity-sensor.patch" "sha256-VviQNjb9SiLREEKGyYXgAGGUk+j9UDTxDUKowg0HXwQ=" ]
    [ "0003-light-support-SSC-light-sensor.patch" "sha256-lcZfEPeGySIK3Prbc+9wD/HAMMscwtAfrS0s4vPUOdk=" ]
    [ "0004-accelerometer-support-SSC-accelerometer-sensor.patch" "sha256-ELfWa5PvZH2xh43KlS8dEcOn04puKXiRhrveybqVwWc=" ]
    [ "0005-compass-support-SSC-compass-sensor.patch" "sha256-XRAjzPtxghYTLMgqTn3n+PsUTNoYXyxkhnoE6ObD9E4=" ]
    [ "0006-data-add-libssc-udev-rules.patch" "sha256-v6G+qVrgWtUzeIZyuRa++eaCdqPHqaHuYXFAci1SyUI=" ]
    [ "0007-data-iio-sensor-proxy.service.in-add-AF_QIPCRTR.patch" "sha256-M0LpXpfgm+Z/taiGqhRTphUwN+U5tSWjZ2Imr5CsV5c=" ]
    [ "0008-drv-ssc-implement-set_polling.patch" "sha256-/uyB/V9JQ6M5YMSZWmbhHEOxbC15LEuTEp4vKpS4RS0=" ]
    [ "0009-tests-integration-test-add-SSC-sensors.patch" "sha256-Wm7C2u9B5I/cniwJdE8Q4MyOxcUR3K5/EV5w+5h10Ms=" ]
    [ "0010-fixup-data-add-libssc-udev-rules.patch" "sha256-v5OEGej0h8VTh8bJ5CWDdpl/VQ5KKuXF5ixVmsaArQM=" ]
    [ "0013-integration-test-add-test-for-sensors-that-report-no.patch" "sha256-Ru/OZ5Cj+IxvdQ0YzfIPyTOOGEJ/4Tl9ifE7LGBak3Y=" ]
  ];
in
stdenv.mkDerivation {
  pname = "sheng-iio-sensor-proxy";
  version = "3.8";

  src = fetchFromGitLab {
    domain = "gitlab.freedesktop.org";
    owner = "hadess";
    repo = "iio-sensor-proxy";
    rev = "3.8";
    hash = "sha256-ZVaV4Aj4alr5eP3uz6SunpeRsMOo8YcZMqCcB0DUYGY=";
  };

  patches = map (p: pmaportsPatch (builtins.elemAt p 0) (builtins.elemAt p 1)) patches_;

  # meson.build queries polkit's own (read-only, out-of-$out) policydir
  # via pkg-config with no override option -- redirect it into $out like
  # udevrulesdir/systemdsystemunitdir already are via mesonFlags below.
  postPatch = ''
    substituteInPlace meson.build \
      --replace-fail \
      "polkit_policy_directory = polkit_gobject_dep.get_pkgconfig_variable('policydir')" \
      "polkit_policy_directory = get_option('prefix') / 'share' / 'polkit-1' / 'actions'"
  '';

  nativeBuildInputs = [ meson ninja pkg-config ];
  buildInputs = [ glib libgudev udev polkit libssc ];

  mesonFlags = [
    "-Dssc-support=true"
    "-Dsystemdsystemunitdir=${placeholder "out"}/lib/systemd/system"
    "-Dudevrulesdir=${placeholder "out"}/lib/udev/rules.d"
  ];

  postInstall = ''
    install -Dm644 ${./10-sheng-sensors.conf} \
      "$out/lib/systemd/system/iio-sensor-proxy.service.d/10-sheng-sensors.conf"
  '';

  meta = {
    description = "IIO sensor to input proxy, with Qualcomm SSC sensor support for sheng";
    license = lib.licenses.gpl3Only;
    platforms = [ "aarch64-linux" ];
  };
}
