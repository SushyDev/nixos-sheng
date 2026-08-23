# Bootloader installer: writes /boot/extlinux/extlinux.conf and the
# per-generation menu file U-Boot imports.
#
# WHY A FORK RATHER THAN boot.loader.generic-extlinux-compatible
#
# The stock module CANNOT WORK on this board. Its builder's addEntry()
# opens with:
#
#     if ! test -e $path/kernel -a -e $path/initrd; then
#         return
#     fi
#
# and nixpkgs only creates $toplevel/initrd when boot.initrd.enable is on
# (system/boot/kernel.nix). This board sets boot.initrd.enable = false
# deliberately -- it is what makes root=PARTLABEL= work without udev --
# so that test fails for EVERY generation and the stock installer emits
# an extlinux.conf containing a header and not one LABEL. Verified on
# hardware: /run/current-system has kernel, dtbs and kernel-params, and
# no initrd. It also emits an unconditional INITRD line pointing at a
# store path that does not exist.
#
# So: fork it. Three deltas from upstream, each forced by this board.
#
#   1. No initrd, anywhere -- neither required nor emitted.
#
#   2. PROMPT 0, and no top-level MENU keyword. A top-level MENU/PROMPT
#      sets cfg->prompt (u-boot boot/pxe_utils.c), which sends U-Boot
#      into menu_interactive_choice() ->
#      cli_readline_into_buffer("Enter choice: ") and matches a TYPED
#      string. This board has three buttons and cannot type digits.
#      Selection is done by U-Boot's own bootmenu instead, which sets
#      pxe_label_override. ("MENU LABEL" *inside* a LABEL block is fine;
#      it goes to parse_label_menu() and does not set prompt.)
#
#   3. Also emits /boot/sheng-bootmenu.env: `bootmenu_<n>=...` lines that
#      sheng.env's loadgenmenu `env import -t`s, one per generation.
#      U-Boot cannot enumerate generations itself -- hush has no
#      directory listing into variables and no command substitution -- so
#      the side that knows has to write them down.
#
# Explicit FDT, never FDTDIR: FDTDIR makes U-Boot resolve a DTB via
# $fdtfile, which sheng.env deliberately does not define, and would leave
# it guessing by compatible string rather than using the overlaid DTB.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.sheng.boot;

  installer = pkgs.writeShellApplication {
    name = "sheng-install-boot";
    runtimeInputs = with pkgs; [
      coreutils
      gnused
      gawk
    ];
    text = ''
      # usage: sheng-install-boot [-d <bootdir>] <toplevel>
      #
      # -d exists so the image builder can populate ./files/boot at build
      # time with exactly the same code that runs at activation time.
      target=/boot
      while getopts "d:" o; do
        case "$o" in
          d) target="$OPTARG" ;;
          *) echo "usage: sheng-install-boot [-d bootdir] <toplevel>" >&2; exit 1 ;;
        esac
      done
      shift $((OPTIND - 1))
      default="$1"
      limit=${toString cfg.configurationLimit}

      mkdir -p "$target/nixos" "$target/extlinux"
      declare -A kept

      # Copy a store path under $target/nixos, flattened to one name, and
      # report that name in the global $result. Idempotent: identical
      # store paths reuse the copy.
      #
      # RESULT COMES BACK IN A GLOBAL, NOT ON STDOUT, and callers must
      # invoke this as `copyIn x; y=$result` rather than `y=$(copyIn x)`.
      # Command substitution runs in a SUBSHELL, so `kept[...]` set inside
      # one is lost to the parent -- which left `kept` empty and made the
      # prune loop below delete every kernel and dtb it had just copied.
      # /boot/nixos ended up empty, extlinux.conf's LINUX pointed at
      # nothing, and U-Boot fell through to the rescue path on every boot.
      # nixpkgs' own extlinux-conf-builder.sh uses this same global-result
      # idiom for the same reason.
      copyIn() {
        local src dst
        src=$(readlink -f "$1")
        dst="$target/nixos/$(echo "$src" | sed 's|^/nix/store/||; s|/|-|g')"
        if [ ! -e "$dst" ]; then
          cp -r "$src" "$dst.tmp.$$"
          mv "$dst.tmp.$$" "$dst"
        fi
        kept["$dst"]=1
        result=$(basename "$dst")
      }

      # $1 = system path, $2 = tag ("default" or a generation number)
      entry() {
        local p k d label params
        p=$(readlink -f "$1")
        # No initrd test -- see the header. Only the kernel is required.
        [ -e "$p/kernel" ] || return 0
        # Not $(copyIn ...) -- see the comment on copyIn.
        copyIn "$p/kernel"; k=$result
        copyIn "$(readlink -m "$p/dtbs")"; d=$result
        label=$(cat "$p/nixos-version")
        params=$(cat "$p/kernel-params")

        printf '\nLABEL nixos-%s\n' "$2"
        if [ "$2" = default ]; then
          printf '  MENU LABEL NixOS - Default\n'
        else
          printf '  MENU LABEL NixOS - Generation %s (%s)\n' "$2" "$label"
        fi
        printf '  LINUX ../nixos/%s\n' "$k"
        printf '  FDT ../nixos/%s/%s\n' "$d" '${cfg.dtbName}'
        printf '  APPEND init=%s/init %s\n' "$p" "$params"
      }

      tmp="$target/extlinux/.extlinux.conf.$$"
      {
        echo "# Generated by sheng-install-boot. Edits are lost on nixos-rebuild."
        echo "DEFAULT nixos-default"
        # See header delta 2. Do NOT add a top-level MENU line.
        echo "PROMPT 0"
        echo "TIMEOUT 1"
        entry "$default" default
      } > "$tmp"

      menutmp="$target/.sheng-bootmenu.env.$$"
      : > "$menutmp"

      # Collected with a glob rather than `ls`: no parsing of ls output,
      # and a glob that matches nothing simply skips the loop body.
      gens=()
      for link in /nix/var/nix/profiles/system-*-link; do
        [ -e "$link" ] || continue
        g=''${link##*/system-}
        g=''${g%-link}
        # Skip anything that is not purely a generation number.
        case "$g" in
          *[!0-9]*) continue ;;
        esac
        gens+=("$g")
      done

      ordered=()
      if [ ''${#gens[@]} -gt 0 ]; then
        mapfile -t ordered < <(printf '%s\n' "''${gens[@]}" | sort -nr | head -n "$limit")
      fi

      # THIS FILE DEFINES THE WHOLE MENU, index 0 included.
      #
      # sheng.env still carries a static bootmenu_0/bootmenu_1, but only
      # as a fallback for when this file is missing or unreadable -- it is
      # not the menu anyone normally sees. Defining index 0 here means the
      # visible entry is named from the system that will actually boot,
      # rather than a string frozen into the bootloader that cannot know
      # which generation it is selecting.
      #
      # `env import` overwrites exactly what this file defines, so the
      # static entries survive if it never loads. There is always a way to
      # boot and always a way into fastboot.
      #
      # cmd/bootmenu.c stops at the first gap, so indices must stay
      # contiguous from 0.

      defpath=$(readlink -f "$default")

      # Which generation is $default? At `nixos-rebuild boot` time its
      # profile link already exists, so this normally resolves. At image
      # build time there are no profile links at all and it stays empty,
      # which is correct -- the image ships one entry for the system baked
      # into it.
      defgen=
      for g in ''${ordered[@]+"''${ordered[@]}"}; do
        if [ "$(readlink -f /nix/var/nix/profiles/system-"$g"-link)" = "$defpath" ]; then
          defgen=$g
          break
        fi
      done

      # Entry 0: the default. No pxe_label_override, so extlinux.conf's
      # own "DEFAULT nixos-default" decides -- which is this same system.
      # Going through DEFAULT rather than naming a label keeps entry 0
      # working even if a generation label is somehow absent.
      if [ -n "$defgen" ]; then
        # Same timestamp source as the entries below, so all rows read
        # alike rather than this one showing a version string.
        defts=$(date '+%Y-%m-%d %H:%M' \
          -d "@$(stat -c %Y /nix/var/nix/profiles/system-"$defgen"-link)")
        deftitle="NixOS generation $defgen ($defts) [current]"
      else
        # Image build time: no profile links exist yet, so there is no
        # generation number or creation time to show. The version label
        # is the only meaningful thing available.
        deflabel=$(cat "$defpath/nixos-version" 2>/dev/null || echo unknown)
        deftitle="NixOS - Default ($deflabel)"
      fi
      printf 'bootmenu_0=%s=setenv pxe_label_override; run bootlinux\n' \
        "$deftitle" >> "$menutmp"

      n=1
      for g in ''${ordered[@]+"''${ordered[@]}"}; do
        link=/nix/var/nix/profiles/system-$g-link
        entry "$link" "$g" >> "$tmp"
        # Already offered as entry 0; listing it twice is just noise.
        [ "$g" = "$defgen" ] && continue
        # stat WITHOUT -L: -L follows the symlink into the store, whose
        # mtime is normalised to the epoch, so every generation rendered
        # as 1970-01-01. The profile link's own mtime is when the
        # generation was actually created.
        ts=$(date '+%Y-%m-%d %H:%M' -d "@$(stat -c %Y "$link")")
        # Title must not contain '=': cmd/bootmenu.c splits on the FIRST
        # one. nixos-version labels and timestamps never do.
        printf 'bootmenu_%d=NixOS generation %s (%s)=setenv pxe_label_override nixos-%s; run bootlinux\n' \
          "$n" "$g" "$ts" "$g" >> "$menutmp"
        n=$((n + 1))
      done

      # Fastboot last. rebootfastboot itself is defined in sheng.env.
      printf 'bootmenu_%d=Reboot to fastboot (bootloader)=run rebootfastboot\n' \
        "$n" >> "$menutmp"

      mv -f "$tmp" "$target/extlinux/extlinux.conf"
      mv -f "$menutmp" "$target/sheng-bootmenu.env"

      # Prune only inside $target/nixos. NEVER touch $target/* directly:
      # /boot/Image and /boot/sm8550-xiaomi-sheng.dtb live there and are
      # what sheng.env's rescue path boots.
      for fn in "$target"/nixos/*; do
        [ -e "$fn" ] || continue
        if [ "''${kept[$fn]:-}" != 1 ]; then
          chmod -R +w -- "$fn"
          rm -rf -- "$fn"
        fi
      done

      sync
    '';
  };
in
{
  options.sheng.boot = {
    configurationLimit = lib.mkOption {
      type = lib.types.int;
      default = 10;
      description = ''
        How many generations U-Boot's menu offers.

        Bounded by three things in increasing tightness: cmd/bootmenu.c's
        MAX_COUNT of 99; space in /boot (~40 MiB of kernel per
        generation, on the root filesystem); and legibility on a panel
        navigated with two volume buttons.
      '';
    };

    dtbName = lib.mkOption {
      type = lib.types.str;
      default = "qcom/sm8550-xiaomi-sheng.dtb";
      description = ''
        Path of the device tree within the generation's `dtbs` directory,
        written into each entry's FDT line.
      '';
    };

    installer = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      description = ''
        The installer itself, exposed so ../rootfs/builder.nix can run it
        at image-build time against `./files/boot` with the same code
        that runs at activation.
      '';
    };
  };

  config = {
    sheng.boot.installer = installer;

    system.build.installBootLoader = lib.getExe installer;
    system.boot.loader.id = "sheng-extlinux";

    # Cannot be used here -- see the header.
    boot.loader.generic-extlinux-compatible.enable = false;
    boot.loader.grub.enable = false;
  };
}
