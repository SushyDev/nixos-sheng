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
{ ... }:
{
  services.pipewire.wireplumber.extraConfig."10-libcamera" = {
    "wireplumber.profiles" = {
      main = {
        "monitor.libcamera" = "required";
      };
    };
  };
}
