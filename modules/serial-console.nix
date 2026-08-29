# USB serial gadget console on ttyGS0. Off by default, and the default is the
# point: binding a gadget to the UDC holds the Type-C port in peripheral mode,
# costing hubs, keyboards and DisplayPort alt mode.
{ config, lib, ... }:

let
  cfg = config.services.shengSerialConsole;
in
{
  options.services.shengSerialConsole = {
    enable = lib.mkEnableOption "the USB serial gadget console on ttyGS0" // {
      description = ''
        Bind the legacy g_serial USB gadget and run a root getty on ttyGS0,
        reachable over the USB-C cable with tio or screen. Costs USB host
        mode while it is on, so leave it off unless you are debugging.

        A freshly flashed image has no WiFi configuration and no authorized
        SSH keys, so with this off the way in is a USB keyboard on tty1.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # Not a ConfigFS gadget: two drivers on one UDC re-enumerate mid-boot and
    # kill serial output.
    boot.kernelModules = [ "g_serial" ];

    # mkBefore because the LAST console= becomes /dev/console, and that must
    # stay tty0 (the panel).
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
