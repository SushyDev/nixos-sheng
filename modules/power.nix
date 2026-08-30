# systemd-sleep writes SuspendState= one value at a time until one succeeds.
# When `mem` aborts (wakeup pending), the fallback reaches `freeze`, and s2idle
# hangs this device hard -- only a forced power-off recovers it. Pinning `mem`
# removes the fallback chain.
{ lib, ... }:

{
  systemd.sleep.settings.Sleep = {
    SuspendState = lib.mkDefault "mem";
    MemorySleepMode = lib.mkDefault "deep";
  };
}
