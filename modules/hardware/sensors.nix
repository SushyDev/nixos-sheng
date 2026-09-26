# Accelerometer, light, proximity and compass, served by the aDSP's Sensor Core.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  sp = pkgs.shengPackages;

  # An open PD handle does not mean SSC registered; libssc retries ~20 s itself.
  waitForSsc = pkgs.writeShellScript "sheng-wait-for-ssc" ''
    exec ${sp.libssc}/bin/ssccli --sensor light --timeout 1 >/dev/null
  '';
in
{
  config = lib.mkIf config.sheng.vendor.enable {
    environment.systemPackages = [
      sp.fastrpc
      sp.libssc
      sp.iio-sensor-proxy
    ];

    systemd.packages = [
      sp.fastrpc
      sp.iio-sensor-proxy
    ];

    services.udev.packages = [
      sp.iio-sensor-proxy
      sp.sheng-sensors
    ];

    systemd.services.iio-sensor-proxy.wantedBy = [ "multi-user.target" ];

    # No ConditionPathExists: systemd checks it once, so a late node skipped the unit all boot.
    systemd.services.adsprpcd-sensorspd = {
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        ExecStartPost = waitForSsc;
        TimeoutStartSec = 60;
      };
    };

    # A mutable copy, because the aDSP writes temp.json back into it.
    systemd.services.sheng-sensors-data = {
      description = "Seed the Qualcomm SSC sensor registry fastrpc serves to the aDSP";
      before = [ "adsprpcd-sensorspd.service" ];
      requiredBy = [ "adsprpcd-sensorspd.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        src=${sp.sheng-sensors}/share/qcom
        if [ "$(cat /var/lib/qcom/.nix-source 2>/dev/null)" != "$src" ]; then
          rm -rf /var/lib/qcom
          mkdir -p /var/lib/qcom
          cp -r --no-preserve=mode,ownership "$src"/. /var/lib/qcom/
          echo "$src" > /var/lib/qcom/.nix-source
        fi
      '';
    };
  };
}
