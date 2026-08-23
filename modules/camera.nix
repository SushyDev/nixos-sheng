# Camera: expose libcamera's cameras to PipeWire.
#
# The kernel side works -- s5kjn1, ov02b1b and ov32d40 all bind, and
# libcamera enumerates all three:
#
#   1: Internal back camera  (cci@ac15000 .. camera@10)
#   2: Internal back camera  (cci@ac16000 .. camera@3c)
#   3: Internal front camera (cci@ac16000 .. camera@10)
#
# But WirePlumber's default profile enables monitor.v4l2 only, so what
# reaches applications is nine raw "Qualcomm Camera Subsystem" CAMSS
# video nodes rather than those cameras -- and an app asking the portal
# for a camera finds nothing usable. Enabling monitor.libcamera is what
# puts the real cameras on the graph.
{ lib, pkgs, ... }:
{
  services.pipewire.wireplumber.extraConfig."10-libcamera" = {
    "wireplumber.profiles" = {
      main = {
        "monitor.libcamera" = "required";

        # And v4l2 OFF. On this SoC the v4l2 monitor exposes the CAMSS
        # pipeline's internal video nodes -- 17 of them, all called
        # "Qualcomm Camera Subsystem" -- which are not cameras and cannot
        # be opened as one. They swamp any camera picker and an app that
        # picks one gets "camera is not supported on the platform". The
        # real cameras all arrive via libcamera.
        "monitor.v4l2" = "disabled";
      };
    };
  };

  # Qt6 defaults QtMultimedia to the FFmpeg backend, which enumerates
  # cameras through V4L2 only -- so a Qt app sees the raw CAMSS video
  # nodes and no usable camera, and reports "no camera detected" even
  # with all three on the PipeWire graph. The GStreamer backend can take
  # them from pipewiresrc instead.
  #
  # Both halves are needed: selecting the backend is useless if GStreamer
  # cannot find the PipeWire element, and nothing puts it on the search
  # path by default. Verified with gst-device-monitor-1.0 Video/Source,
  # which then lists "Built-in Front Camera" (ov32d40, location=front)
  # and the back cameras.
  environment.sessionVariables = {
    QT_MEDIA_BACKEND = "gstreamer";
    GST_PLUGIN_SYSTEM_PATH_1_0 = lib.makeSearchPath "lib/gstreamer-1.0" [
      pkgs.gst_all_1.gst-plugins-base
      pkgs.gst_all_1.gst-plugins-good
      pkgs.pipewire
      pkgs.libcamera
    ];
  };
}
