# Every sheng vendor userspace package, as one scope so they can depend on
# each other by name. Consumed by modules/hardware/.
{
  lib,
  newScope,
  libssc,
  iio-sensor-proxy,
}:

lib.makeScope newScope (self: {
  # The aDSP registers its sensors one by one over ~20 s after boot, which
  # upstream gives up on; and overlapping opens corrupt its report handlers.
  # Each patch says why.
  libssc = libssc.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [
      ./libssc/0100-retry-the-ssc-lookup-without-blocking-the-main-loop.patch
      ./libssc/0101-retry-sensor-discovery-while-the-adsp-registers.patch
      ./libssc/0102-give-each-request-its-own-report-handler.patch
    ];
  });
  # Its SSC discovery takes those ~20 s, and KWin asks before it finishes.
  iio-sensor-proxy = (iio-sensor-proxy.override { inherit (self) libssc; }).overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [
      ./iio-sensor-proxy/0100-broadcast-sensor-availability-changes.patch
      ./iio-sensor-proxy/0101-start-polling-for-claims-made-during-discovery.patch
      ./iio-sensor-proxy/0102-discover-the-ssc-accelerometer-first.patch
    ];
  });

  alsa-ucm-sheng = self.callPackage ./alsa-ucm-sheng { };
  fastrpc = self.callPackage ./fastrpc { };
  sheng-charger-mode = self.callPackage ./sheng-charger-mode { };
  sheng-devauth = self.callPackage ./sheng-devauth { };
  sheng-fingerprint = self.callPackage ./sheng-fingerprint { };
  sheng-firmware-blobs = self.callPackage ./sheng-firmware-blobs { };
  sheng-keyboard-helper = self.callPackage ./sheng-keyboard-helper { };
  sheng-mipps-auth = self.callPackage ./sheng-mipps-auth { };
  sheng-pen-status = self.callPackage ./sheng-pen-status { };
  sheng-sensors = self.callPackage ./sheng-sensors { };
  sheng-thp = self.callPackage ./sheng-thp { };
})
