{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.sheng.camera;
  wireplumber = config.services.pipewire.enable && config.services.pipewire.wireplumber.enable;
in
{
  options.sheng.camera = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Swap WirePlumber's V4L2 monitor for the libcamera one, so apps see
        cameras instead of raw CAMSS video nodes.
      '';
    };

    qtGstreamerBackend = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Point Qt Multimedia at GStreamer system-wide, with a plugin path
        containing the PipeWire element. Off by default because it changes the
        media backend for every Qt app; without it Qt's FFmpeg backend goes
        through V4L2 only and reports "no camera detected".
      '';
    };
  };

  config = lib.mkMerge [
    (lib.mkIf (cfg.enable && wireplumber) {
      services.pipewire.wireplumber.extraConfig."10-libcamera" = {
        "wireplumber.profiles" = {
          main = {
            "monitor.libcamera" = "required";
            "monitor.v4l2" = "disabled";
          };
        };
      };
    })

    (lib.mkIf cfg.qtGstreamerBackend {
      environment.sessionVariables = {
        QT_MEDIA_BACKEND = "gstreamer";
        GST_PLUGIN_SYSTEM_PATH_1_0 = lib.makeSearchPath "lib/gstreamer-1.0" [
          pkgs.gst_all_1.gst-plugins-base
          pkgs.gst_all_1.gst-plugins-good
          pkgs.pipewire
          pkgs.libcamera
        ];
      };
    })
  ];
}
