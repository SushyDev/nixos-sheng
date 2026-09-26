# zram, systemd-oomd and a deprioritised nix-daemon, so an on-device rebuild
# does not stall the session. Measured on this hardware by DotRedstone/nixos-sheng.
{
  config,
  lib,
  ...
}:

{
  options.sheng.performance.enable = lib.mkEnableOption "zram swap, systemd-oomd and a deprioritised nix-daemon";

  config = lib.mkIf config.sheng.performance.enable {
    zramSwap = {
      enable = lib.mkDefault true;
      algorithm = lib.mkDefault "zstd";
      memoryPercent = lib.mkDefault 50;
      priority = lib.mkDefault 100;
    };

    boot.kernel.sysctl = {
      "vm.swappiness" = lib.mkDefault 100;
      "vm.page-cluster" = lib.mkDefault 0;
    };

    systemd.oomd = {
      enable = lib.mkDefault true;
      enableUserSlices = lib.mkDefault true;
    };

    nix.settings = {
      max-jobs = lib.mkDefault 2;
      cores = lib.mkDefault 4;
    };
    systemd.services.nix-daemon.serviceConfig = {
      CPUWeight = lib.mkDefault 50;
      IOSchedulingClass = lib.mkDefault "best-effort";
      IOSchedulingPriority = lib.mkOverride 90 6;
    };

    # Held boot for ~18 s with nothing needing the network before login.
    systemd.services.NetworkManager-wait-online.wantedBy = lib.mkForce [ ];

    services.journald.settings.Journal.SystemMaxUse = lib.mkDefault "512M";
  };
}
