# USB serial gadget console on ttyGS0.
#
# Off by default, and the default is the point: binding a gadget driver to
# the UDC holds the Type-C port in peripheral mode, so the tablet cannot
# act as a USB host. With this disabled the port is free to do what a
# tablet's port is normally for -- hubs, keyboards, mice, DisplayPort alt
# mode. With it enabled you get a root console over the same cable, which
# is what you want while bringing the device up and not much use after.
#
# The mechanism is CONFIG_USB_G_SERIAL. It used to be =y, which auto-binds
# the UDC at boot with no userspace step and therefore could not be turned
# off at all. It is =m now (see packages/kernel/default.nix) so that this
# option can decide, and the module is loaded only when it is on.
{ config, lib, ... }:

let
  cfg = config.services.shengSerialConsole;
in
{
  options.services.shengSerialConsole = {
    enable = lib.mkEnableOption "the USB serial gadget console on ttyGS0" // {
      description = ''
        Bind the legacy g_serial USB gadget and run a root getty on
        ttyGS0, reachable over the USB-C cable with tio or screen.

        Enabling this costs USB host mode: the port stays a peripheral,
        so hubs, keyboards and DisplayPort alt mode will not work while
        it is on. Leave it off unless you are debugging.

        Note that a freshly flashed image has no WiFi configuration and
        no authorized SSH keys, so with this off the way in is a USB
        keyboard on tty1 (which autologins) rather than a serial cable.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # g_serial rather than a ConfigFS gadget service: two gadget drivers
    # on one UDC re-enumerate mid-boot and kill serial output.
    boot.kernelModules = [ "g_serial" ];

    # mkBefore so this lands ahead of hardware.nix's console= entries.
    # The LAST console= on the command line becomes /dev/console, and that
    # must stay tty0 (the panel) -- appending here would silently steal it.
    boot.kernelParams = lib.mkBefore [ "console=ttyGS0" ];

    systemd.services."serial-getty@ttyGS0" = {
      enable = true;
      wantedBy = [ "multi-user.target" ];
      # The base template references $TERM but never sets it on this tty;
      # unset, agetty dies with "checkname failed". Restart=always so a USB
      # re-enumeration does not leave the console dead.
      environment.TERM = "vt102";
      serviceConfig.Restart = "always";
      serviceConfig.RestartSec = "1";
    };
  };
}
