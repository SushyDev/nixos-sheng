# zram, VM tuning for zram-only swap, systemd-oomd and a deprioritised
# nix-daemon, so an on-device rebuild does not stall the session. Measured on
# this hardware by DotRedstone/nixos-sheng.
{
  config,
  lib,
  ...
}:

{
  options.sheng.performance.enable = lib.mkEnableOption "zram swap, systemd-oomd and a deprioritised nix-daemon";

  config = lib.mkIf config.sheng.performance.enable {
    # 8G soldered and zram is the only swap. zstd runs ~3:1 on desktop anon
    # pages, so a device the size of RAM costs well under half of it when full.
    zramSwap = {
      enable = lib.mkDefault true;
      algorithm = lib.mkDefault "zstd";
      memoryPercent = lib.mkDefault 100;
      priority = lib.mkDefault 100;
    };

    # Tuned for swap that is RAM: prefer compressing idle anon over dropping
    # page cache, no readahead (each page is its own zram slot), and wake
    # kswapd earlier instead of boosting after fragmentation events.
    boot.kernel.sysctl = {
      "vm.swappiness" = lib.mkDefault 180;
      "vm.page-cluster" = lib.mkDefault 0;
      "vm.watermark_boost_factor" = lib.mkDefault 0;
      "vm.watermark_scale_factor" = lib.mkDefault 125;
    };

    # THP=always (the kernel config default) lets khugepaged back sparse
    # heaps with 2M pages; madvise keeps huge pages for the apps that ask.
    boot.kernelParams = [ "transparent_hugepage=madvise" ];

    # MGLRU thrashing protection: keep the working set of the last second
    # resident and let the OOM killer act instead of livelocking.
    systemd.tmpfiles.rules = [
      "w- /sys/kernel/mm/lru_gen/min_ttl_ms - - - - 1000"
    ];

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
      # Builds inherit this, so the kernel OOM killer takes a compiler before
      # the compositor.
      OOMScoreAdjust = lib.mkDefault 500;
    };

    # Held boot for ~18 s with nothing needing the network before login.
    systemd.services.NetworkManager-wait-online.wantedBy = lib.mkForce [ ];

    services.journald.settings.Journal.SystemMaxUse = lib.mkDefault "512M";
  };
}
