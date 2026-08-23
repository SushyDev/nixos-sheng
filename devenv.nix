{ pkgs, lib, ... }:

# Build/flash loop for the sheng NixOS image, cross-built for aarch64-linux
# on the `sheng-nix-builder` Docker/OrbStack container (this repo is worked
# on from aarch64-darwin, which can't build aarch64-linux directly without a
# remote/linux builder). `docker exec` into that container doesn't work (a
# runc/OrbStack issue with this Nix image's symlinked /etc/passwd), so this
# talks to it over the SSH bridge on localhost:2222 instead, using a
# throwaway keypair already added to the container's authorized_keys.
#
# NOTE: tried switching this to Determinate Nix's native Linux builder
# (https://docs.determinate.systems/troubleshooting/native-linux-builder/)
# -- the `nix build` plumbing itself works (see git history of this file
# for that version), but the builder VM has no working DNS/network at all
# (confirmed with a trivial nixpkgs fetchurl test), which breaks every
# fixed-output derivation in this flake's closure. Plain fetchurl/
# fetchFromGitHub fetches can be worked around by vendoring content into
# the local store by hash ahead of time, but firmware/iio-sensor-proxy.nix's
# fetchpatch calls normalize patch text *inside* the sandboxed builder
# before hashing, which can't be faked from outside. Reverted to this
# known-working container/SSH path until the VM's networking is fixed
# upstream.
let
  # ssh takes -p for the port, scp takes -P -- these can't share one opts
  # string despite otherwise-identical flags.
  sshOpts = "-i .devenv-build/builder_key -p 2222 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o IdentitiesOnly=yes";
  scpOpts = "-i .devenv-build/builder_key -P 2222 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o IdentitiesOnly=yes";
  builder = "root@localhost";
in
{
  packages = [ pkgs.openssh ];

  tasks."nixos:build" = {
    description = "Sync source to sheng-nix-builder and build .#shengImage remotely";
    exec = ''
      set -euo pipefail
      mkdir -p .devenv-build

      echo "→ packing source..."
      tar --exclude='.git' --exclude='result' --exclude='result-*' --exclude='.devenv' --exclude='.devenv-build' \
        -czf .devenv-build/src.tar.gz .

      echo "→ copying to builder..."
      scp ${scpOpts} -o ConnectTimeout=10 .devenv-build/src.tar.gz ${builder}:/root/nixos-src.tar.gz

      echo "→ extracting on builder..."
      ssh ${sshOpts} -o ConnectTimeout=10 ${builder} \
        'rm -rf /root/sheng-nixos && mkdir -p /root/sheng-nixos && tar -xzf /root/nixos-src.tar.gz -C /root/sheng-nixos'

      echo "→ building (streamed, not buffered -- a stall here shows up immediately instead of going silent)..."
      # ServerAliveInterval/CountMax so a dead-but-not-closed connection surfaces
      # as an error within ~30s instead of hanging indefinitely.
      ssh ${sshOpts} -o ServerAliveInterval=10 -o ServerAliveCountMax=3 ${builder} \
        'cd /root/sheng-nixos && nix build --no-link --print-out-paths --print-build-logs .#shengImage' \
        | tee .devenv-build/last-build-path.txt

      out_path=$(tail -n1 .devenv-build/last-build-path.txt)
      if [ -z "$out_path" ]; then
        echo "✗ build produced no output path -- see above for where it stopped" >&2
        exit 1
      fi
      echo "✓ Built: $out_path"
    '';
  };

  tasks."nixos:fetch-image" = {
    description = "Copy the built sparse+raw rootfs image out of the container into result/";
    exec = ''
      set -euo pipefail
      store_path=$(tail -n1 .devenv-build/last-build-path.txt)
      container_path="/Users/sushy/OrbStack/docker/containers/sheng-nix-builder/nix/store/$(basename "$store_path")"
      mkdir -p result
      rm -f result/sheng-rootfs.img result/sheng-rootfs.sparse.img
      cp "$container_path/sheng-rootfs.img" result/sheng-rootfs.img
      cp "$container_path/sheng-rootfs.sparse.img" result/sheng-rootfs.sparse.img
      ls -lah result/sheng-rootfs.img result/sheng-rootfs.sparse.img
    '';
  };
}
