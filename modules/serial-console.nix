# USB serial gadget console on ttyGS0. Off by default: binding a gadget to the
# UDC holds the Type-C port in peripheral mode, costing hubs, keyboards and
# DisplayPort alt mode.
{ config, lib, ... }:

let
  cfg = config.services.shengSerialConsole;
in
{
  options.services.shengSerialConsole = {
    enable = lib.mkEnableOption "the USB serial gadget console on ttyGS0" // {
      description = ''
        Bind the legacy g_serial USB gadget and run a root getty on ttyGS0.
        Costs USB host mode while on, so leave it off unless debugging.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # Not a ConfigFS gadget: two drivers on one UDC re-enumerate mid-boot and
    # kill serial output.
    boot.kernelModules = [ "g_serial" ];

    # mkBefore because the LAST console= becomes /dev/console, which must stay
    # tty0 (the panel).
    boot.kernelParams = lib.mkBefore [ "console=ttyGS0" ];

    systemd.services."serial-getty@ttyGS0" = {
      enable = true;
      wantedBy = [ "multi-user.target" ];
      # Unset, agetty dies with "checkname failed".
      environment.TERM = "vt102";
      serviceConfig.Restart = "always";
      serviceConfig.RestartSec = "1";
    };
  };
}
