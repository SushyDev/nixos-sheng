# Accelerometer, light, proximity and compass, served by the aDSP's Sensor Core.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  sp = pkgs.shengPackages;
in
{
  config = lib.mkIf config.sheng.vendor.enable {
    hardware.sensor.iio = {
      enable = true;
      package = sp.iio-sensor-proxy;
    };

    # Upstream's rule tags the aDSP with the SSC sensors every board has; this
    # adds the accelerometer, proximity and the accelerometer's mount matrix.
    services.udev.packages = [ sp.sheng-sensors ];

    # ssccli, to query the Sensor Core directly.
    environment.systemPackages = [ sp.libssc ];

    systemd.services.adsprpcd-sensorspd = {
      description = "aDSP RPC daemon for the sensors PD";
      wantedBy = [ "multi-user.target" ];

      # The aDSP reads its sensor registry from here and writes temp.json back,
      # so it is a mutable copy, reseeded when the package changes.
      preStart = ''
        src=${sp.sheng-sensors}/share/qcom
        if [ "$(cat .nix-source 2>/dev/null)" != "$src" ]; then
          find . -mindepth 1 -delete
          cp -r --no-preserve=mode,ownership "$src"/. .
          echo "$src" > .nix-source
        fi
      '';

      serviceConfig = {
        Type = "exec";
        ExecStart = "${sp.fastrpc}/bin/adsprpcd sensorspd";
        # An open PD handle does not mean SSC registered; libssc retries ~20 s.
        ExecStartPost = "${lib.getExe' sp.libssc "ssccli"} --sensor light --timeout 1";
        TimeoutStartSec = 60;
        Restart = "on-failure";
        RestartSec = 5;
        StateDirectory = "qcom";
        WorkingDirectory = "/var/lib/qcom";
      };
    };

    systemd.services.iio-sensor-proxy = {
      wantedBy = [ "multi-user.target" ];
      wants = [ "adsprpcd-sensorspd.service" ];
      after = [ "adsprpcd-sensorspd.service" ];
    };
  };
}
