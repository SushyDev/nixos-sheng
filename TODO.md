# TODO

Known-unfinished hardware work, with what has already been ruled out so the
next person does not repeat it. Everything here was measured on hardware.

---

## Auto-rotate — blocked on the ADSP dropping the sensor PD

**Symptom.** No auto-rotate. `iio-sensor-proxy` runs but reports
`HasAccelerometer false`, and `ssccli --sensor accelerometer` fails with
`SSC QMI Service not found`.

The accelerometer is only reachable through Qualcomm's SSC stack on the ADSP:
`/sys/bus/iio/devices` is empty, so there is no kernel IIO accelerometer to
fall back to. No SSC means no rotation, full stop.

**Fixed on the way here** (`fastrpc: give adsprpcd an RPATH to its own
libraries`). `adsprpcd` could not `dlopen libadsp_default_listener.so.1` and
restart-looped forever, because `postInstall` copies `src/adsprpcd` straight
out of the build tree and so bypasses libtool's install step, leaving an
RPATH of glibc only. Every downstream symptom pointed somewhere else. That
error is gone.

**Where it stops now.** With the library loading, the next failure appears:

```
adsp_default_listener.c:380: error 114: remote_handle_open("adsp_default_listener")
dsprpcd.c:114: fastRPC device is not accessible, daemon exiting...
```

and `dmesg` shows the **ADSP restarting during the attempt** — `PDR:
Indication received from msm/adsp/audio_pd` and `charger_pd` reappear
mid-run. So opening the sensor PD appears to bring the DSP down.

**Ruled out already:**

- Not the udev tagging. `IIO_SENSOR_PROXY_TYPE=ssc-accel ...` and
  `ACCEL_MOUNT_MATRIX` are both correctly set on `/sys/class/misc/fastrpc-adsp`.
- Not missing firmware. `adsp.mbn`, `adsp_dtb.mbn` and the `.jsn` files are
  byte-identical to `references/sheng-firmware`.
- Not `iio-sensor-proxy` itself. It is installed, enabled and running; it
  simply finds no accelerometer to expose.
- Not the "sensor daemon races the ADSP" theory. Tested and wrong, and note
  that `wantedBy = mkForce [ ]` does **not** stop either
  `adsprpcd-sensorspd` or `iio-sensor-proxy` — udev/D-Bus activation starts
  them regardless, which invalidated two attempts before this was noticed.

**Next step.** Compare against debian-sheng directly rather than reasoning
about it: it runs the same daemon, the same firmware and reportedly has
working sensors, so a runtime diff (dmesg around the PD open, module load
order, what starts `adsprpcd` and when) should show what differs. Possibly
related to the `qcom-apm gprsvc: CMD timeout for [1001021] opcode` seen on
every boot — both are the ADSP not answering.

---

## Third camera (ov02b1b) — blocked upstream in libcamera

**Symptom.** Camera apps offer two cameras, not three.

The device has 1 front and 2 back sensors. Working: `s5kjn1` (main back) and
`ov32d40` (front). Not working: `ov02b1b` (secondary back).

**Cause.** `ov02b1b` emits `R10_CSI2P` — packed 10-bit Bayer — and
libcamera's CPU debayer rejects that format:

```
INFO Debayer debayer_cpu.cpp:331 Unsupported input format R10_CSI2P
INFO Camera camera_manager.cpp:223 Adding camera '.../cci@ac16000/i2c-bus@0/camera@3c'
```

(`camera@3c` is the ov02b1b, I²C address 0x3c.) The camera registers and
appears on the PipeWire graph, but can never produce a usable stream, so
GStreamer correctly drops it and applications see two. This is not a
configuration problem.

**Possible routes**, both upstream work rather than config:

- Add `R10_CSI2P` support to libcamera's `debayer_cpu.cpp`.
- Have the CAMSS pipeline hand over an unpacked 10-bit variant instead.

Worth checking whether debian-sheng exposes all three — if it does, this is
solvable and the difference is worth finding.

**Ruled out already:** the kernel sensor drivers are present and all three
sensors bind; libcamera's `Failed to create camera sensor helper` warnings
are not fatal (`cam -l` lists all three cameras with those warnings present).

---

## Touchscreen shows no device name in KDE

**Symptom.** Touch input works, but KDE's touchscreen settings shows
`Device: <blank>` and an empty, greyed-out dropdown.

**Cause.** The nt36532e driver registers its input devices with no parent:

```
NVTCapacitiveTouchScreen -> /virtual/input/input3
NVTCapacitivePenM80p     -> /virtual/input/input4
NVTCapacitivePenP81c     -> /virtual/input/input5
```

Because `input_dev->dev.parent` is never set they land under
`/devices/virtual/`, so udev exposes only `ID_INPUT=1` and
`ID_INPUT_TOUCHSCREEN=1` — no `ID_PATH`, no vendor or model strings — and
KWin has nothing to identify the device with or map to an output.

The device itself is fine: name `NVTCapacitiveTouchScreen`, vendor `0x2717`
(Xiaomi), product `0x3653`, bus `0x0006`, on `/dev/input/event3`.

**Fix.** A one-line change in the driver to point `dev.parent` at the SPI
device (and ideally fill `input->id.*` and `->phys` too). That belongs
upstream in ianchb's experimental nt36532e driver, or as a patch carried in
`packages/kernel`. A udev rule cannot properly substitute for a missing
parent.

Note the DSI panel also reports 0 bytes of EDID, which is normal for an
internal panel but means there is no display name to pair a touchscreen
with either.

---

## Smaller things

- **Qrca cannot use the cameras.** Its Qt backend consumes neither libcamera
  nor PipeWire here and reports "camera is not supported on the platform".
  Snapshot and Kamoso (GStreamer) work. `libcamerify <app>` is the shim for
  V4L2-only applications.
- **Greeter on-screen keyboard is unverified.** `modules/virtual-keyboard.nix`
  gives SDDM's kwin greeter the `--inputmethod plasma-keyboard` that nixpkgs
  omits, which is why the Breeze theme's keyboard button does nothing. Reasoned
  from the nixpkgs and KDE sources and eval-checked, **not measured**. On the
  device, check that a keyboard appears, that `pgrep plasma-keyboard` finds a
  process while the greeter is up, and that `journalctl -u display-manager` is
  free of kwin input-method errors.
- **Cold-boot verification owed.** The audio, camera and Maliit fixes have
  all been applied with `nixos-rebuild switch` plus service restarts. The
  ordering of `sheng-alsa-ucm.service` against the sound card appearing has
  not been proven from a cold boot.
- **`iio-sensor-proxy` crashes on startup** (`client_vanished_cb` asserting
  on a NULL hash table) and survives a manual restart. Secondary to the SSC
  problem above, but it is an upstream bug worth reporting.
