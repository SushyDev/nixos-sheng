# U-Boot

Source: [SushyDev/u-boot](https://github.com/SushyDev/u-boot). The device has no UART, so
the display came first.

- **Display driver in Zig**: SM8550 MDSS, dual DSI and DSC for the 3048×2032 144 Hz panel.
- **No black gap**: a `splash_region` node makes Xiaomi's bootloader hand over a live
  display, which U-Boot keeps running untouched.
- **Boot menu** on the volume and power keys: every NixOS generation, and reboot to
  fastboot (via the IMEM restart cookie; ABL ignores the Android handshake).
- **Plugging in a charger** waits for POWER instead of booting Linux.
- **Upstream fixes**: early stack placement, the reserved-memory limit, SM8550 power
  domains, GENI firmware loading.

Not supported: fastboot or USB serial from U-Boot, dual-boot.
