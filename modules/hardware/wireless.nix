# Factory Wi-Fi and Bluetooth addresses from Android's persist partition.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  persist = "/mnt/persist";

  # ath12k reads its MAC from this firmware path.
  wlanMacLink = pkgs.runCommand "sheng-wlan-mac-link" { } ''
    mkdir -p "$out/lib/firmware/ath12k/WCN7850/hw2.0"
    ln -s ${persist}/kiwi_v2/wlan_mac.bin "$out/lib/firmware/ath12k/WCN7850/hw2.0/wlan_mac.bin"
  '';

  btmgmt = "${pkgs.bluez}/bin/btmgmt";
in
{
  options.sheng.factoryAddresses.enable =
    lib.mkEnableOption "the factory Wi-Fi and Bluetooth addresses from the persist partition"
    // {
      default = true;
    };

  config = lib.mkIf config.sheng.factoryAddresses.enable {
    # persist holds calibration nothing can regenerate: read-only, no journal replay, no fsck.
    fileSystems.${persist} = {
      device = "/dev/disk/by-partlabel/persist";
      fsType = "ext4";
      noCheck = true;
      options = [
        "ro"
        "noload"
        "nosuid"
        "nodev"
        "noexec"
        "nofail"
        "x-systemd.device-timeout=10s"
      ];
    };

    hardware.firmware = [ wlanMacLink ];

    # ath12k reads the address once at probe, and udev would probe before persist mounts.
    boot.blacklistedKernelModules = [ "ath12k_wifi7" ];
    systemd.services.sheng-wlan = {
      description = "Load Wi-Fi once its factory address is readable";
      wants = [ "mnt-persist.mount" ];
      after = [ "mnt-persist.mount" ];
      before = [ "NetworkManager.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${pkgs.kmod}/bin/modprobe ath12k_wifi7";
      };
    };

    systemd.services.sheng-bluetooth-address = lib.mkIf config.hardware.bluetooth.enable {
      description = "Set the factory Bluetooth address";
      wants = [ "mnt-persist.mount" ];
      after = [
        "mnt-persist.mount"
        "bluetooth.service"
      ];
      requires = [ "bluetooth.service" ];
      wantedBy = [ "bluetooth.target" ];
      path = [
        pkgs.coreutils
        pkgs.gawk
      ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        nv=${persist}/bluetooth/.bt_nv.bin
        [ -r "$nv" ] || { echo "no $nv; keeping the controller's address"; exit 0; }

        read -r -a octets <<< "$(od -An -tx1 -N6 "$nv")"
        [ "''${#octets[@]}" = 6 ] || { echo "$nv is too short" >&2; exit 1; }
        printf -v addr '%s:%s:%s:%s:%s:%s' "''${octets[@]}"
        addr=''${addr^^}

        current() { ${btmgmt} info 2>/dev/null | awk '/addr / { print $2; exit }'; }

        for _ in $(seq 50); do [ -n "$(current)" ] && break; sleep 0.1; done
        [ "$(current)" = "$addr" ] && exit 0

        ${btmgmt} power off || true
        ${btmgmt} public-addr "$addr"
        for _ in $(seq 50); do [ "$(current)" = "$addr" ] && exit 0; sleep 0.1; done
        echo "controller did not take $addr" >&2
        exit 1
      '';
    };
  };
}
