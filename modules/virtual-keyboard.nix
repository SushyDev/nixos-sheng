# An on-screen keyboard for SDDM. The device has no built-in keyboard, so a
# greeter without one cannot be logged into. Inert unless a host enables SDDM.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.displayManager.sddm;
  kwinGreeter = cfg.enable && cfg.wayland.enable && cfg.wayland.compositor == "kwin";
in
{
  # nixpkgs sets General.InputMethod = "" for the kwin greeter but never passes
  # kwin --inputmethod, so Breeze's keyboard button toggles a panel with no
  # input-method server behind it. Appended through settings rather than
  # replacing wayland.compositorCommand, so later kwin flags are inherited.
  # UNVERIFIED ON HARDWARE -- see TODO.md.
  config = lib.mkIf kwinGreeter {
    services.displayManager.sddm.settings.Wayland.CompositorCommand =
      "${cfg.wayland.compositorCommand} "
      + "--inputmethod ${lib.getExe' pkgs.kdePackages.plasma-keyboard "plasma-keyboard"}";
  };
}
