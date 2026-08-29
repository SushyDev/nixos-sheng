# Expose libcamera's cameras to PipeWire. WirePlumber's default profile
# enables monitor.v4l2 only, so applications see raw CAMSS video nodes rather
# than cameras.
{ lib, pkgs, ... }:
{
  services.pipewire.wireplumber.extraConfig."10-libcamera" = {
    "wireplumber.profiles" = {
      main = {
        "monitor.libcamera" = "required";

        "monitor.v4l2" = "disabled";
      };
    };
  };

  # Qt6's default FFmpeg backend enumerates through V4L2 only, so a Qt app
  # reports "no camera detected". Both halves are needed: the GStreamer
  # backend, and a search path where it can find the PipeWire element.
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
