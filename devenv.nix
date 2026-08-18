{ pkgs, lib, ... }:

# Build/flash loop for the sheng NixOS image, cross-built for aarch64-linux
# on the `sheng-nix-builder` Docker/OrbStack container (this repo is worked
# on from aarch64-darwin, which can't build aarch64-linux directly without a
# remote/linux builder). `docker exec` into that container doesn't work (a
# runc/OrbStack issue with this Nix image's symlinked /etc/passwd), so this
# talks to it over the SSH bridge on localhost:2222 instead, using a
# throwaway keypair already added to the container's authorized_keys.
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
      tar --exclude='.git' --exclude='result' --exclude='result-*' --exclude='.devenv' --exclude='.devenv-build' \
        -czf .devenv-build/src.tar.gz .
      scp ${scpOpts} .devenv-build/src.tar.gz ${builder}:/root/nixos-src.tar.gz
      ssh ${sshOpts} ${builder} \
        'rm -rf /root/sheng-nixos && mkdir -p /root/sheng-nixos && tar -xzf /root/nixos-src.tar.gz -C /root/sheng-nixos'
      ssh ${sshOpts} ${builder} 'cd /root/sheng-nixos && nix build --no-link --print-out-paths .#shengImage' \
        | tee .devenv-build/last-build-path.txt
      echo "✓ Built: $(cat .devenv-build/last-build-path.txt)"
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
