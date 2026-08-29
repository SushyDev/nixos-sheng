# TODO

Unfinished hardware work, plus the odd solved case whose false leads are worth
keeping. Everything here was measured on hardware.

---

## SOLVED — the ADSP crash loop (battery, sensors, MiPPS)

Kept because the symptoms pointed everywhere except the cause.

**Symptoms.** Every `/sys/class/power_supply/qcom-battmgr-bat/*` read returned
`EAGAIN`; `upower` showed 0% and `battery-missing`. No auto-rotate,
`HasAccelerometer false`. `xiaomi-mipps-auth` failed with `Read returned None`
on the pmic-glink `xiaomi` node.

**Cause.** One thing: the ADSP was crashing and recovering roughly every five
seconds, 76 times in the first eight minutes.

```
PDM: service 'sensor_process' crash: 'EF:sensor_process:0x4:sns_registry:0x6b:sns_registry_s'
qcom_q6v5_pas 6800000.remoteproc: fatal error received: err_qdi.c:1211:...:sns_registry_sensor.c:329:SNS_RC_SUCCESS == rc
```

`sns_registry` aborts the whole ADSP when it cannot read its registry, and it
reads it back over fastrpc from the AP's filesystem. fastrpc is compiled with
`CONFIG_BASE_DIR=/usr/share/qcom` (configure.ac default), reads
`$CONFIG_BASE_DIR/conf.d/*.yaml`, matches `/sys/firmware/devicetree/base/model`
against the machine key, and uses that machine's `DSP_LIBRARY_PATH` relative to
`CONFIG_BASE_DIR`. Debian's `sheng-sensors` deb unpacks straight to
`/usr/share/qcom`, so it works there. The Nix derivation copied the same tree
to `$out/usr/share/qcom` — a path no profile links — so the search path was
empty. Everything else rides on the ADSP: `qcom_battmgr` and the `xiaomi`
power-supply node are pmic-glink endpoints on that same DSP.

Fixed by `--with-config-base-dir=/var/lib/qcom` plus the `sheng-sensors-data`
unit that seeds it. It has to be a writable copy, not the store path: the DSP
writes `temp.json` back into the tree.

The registry has to be there **before the ADSP boots**. Putting it in place on
a running system stops the crash loop but the sensor PD never registers QMI
service 400, so `ssccli` keeps reporting `SSC QMI Service not found`; only
after `echo stop/start > /sys/class/remoteproc/remoteproc0/state` does
`qrtr-DEBUG` show `added server on 5:21 -> service 400`. From a cold boot the
seed unit orders before `adsprpcd-sensorspd`, so this is a debugging note, not
a remaining bug.

**Everything else matched debian-sheng and was not the problem** — same kernel
tree and `sm8550.config`, same fastrpc v1.0.2, same libssc with the same
`wait_for_qmi_service.patch`, same iio-sensor-proxy patch set, and all 276
sensor data files byte-identical.

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
- **`iio-sensor-proxy` takes ~20 s to expose all four sensors.** libssc waits
  5 s for the QRTR bus on every `discover`, and there are four SSC drivers, so
  auto-rotate only becomes available about 25 s after boot. Three fixes live
  in `packages/firmware/iio-sensor-proxy/`, all worth sending upstream:
  pmaports' no-exit patch left the client tables NULL (`0100-`), the SSC
  drivers tore down a sensor that lazy-create had never made (`0101-`),
  availability was only ever signalled to clients holding a claim, so KWin
  never learned the accelerometer had shown up (`0102-`), and a claim that
  arrived during the discovery wait was recorded but never started polling
  (`0103-`).
- **KWin never re-enables the sensor on its own.** `availableChanged` only
  reaches `setAutoRotateAvailable()`, so the capability comes back but
  `applySensorChanges()` — the sole caller of `OrientationSensor::setEnabled`
  — is wired to lid, tablet-mode and reading events only. Upstream that gap
  is unreachable because availability never changes after startup. `0103-`
  covers it from our side by honouring the claim KWin already made; a real
  fix belongs in KWin.
- **Auto-rotate defaults to `inTabletMode` and `tabletMode` is always false.**
  `gpio-keys` advertises `SW_TABLET_MODE` but nothing drives it, so the policy
  has to be set to Always in System Settings for rotation to actually fire.
- **Two cosmetic libssc complaints**, neither fatal: `Mount matrix provided by
  firmware is all 0` (the udev rule supplies `ACCEL_MOUNT_MATRIX` anyway) and
  `Failed to unpack Xiaomi Davinci proximity measurement message`.
