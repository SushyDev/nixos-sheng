# aarch64-linux Nix builder, driven with `docker exec`.
#
# Determinate's native Linux builder cannot be used: its VM has no
# network, so fixed-output derivations that are not already in a cache
# fail to fetch (DeterminateSystems/nix-src#294).
FROM nixos/nix:latest

# git-minimal already ships in the base image; installing git collides.
RUN nix-env -iA nixpkgs.bash

ENV PATH=/root/.nix-profile/bin:/usr/bin:/bin

# /etc/passwd, /etc/group and /etc/nix/nix.conf are symlinks into
# /nix/store, and the named volume on /nix shadows them with whatever it
# was seeded from -- so edits made here silently do not apply at runtime.
# Replace them with real files first.
#
# De-symlinking the account files also makes `docker exec` work: runc
# refuses a container whose /etc/passwd escapes the rootfs.
RUN for f in /etc/passwd /etc/group /etc/nix/nix.conf; do \
      cp -L "$f" "$f.real" && rm -f "$f" && mv "$f.real" "$f"; \
    done

RUN printf '%s\n' \
      'experimental-features = nix-command flakes' \
      'sandbox = false' \
      'max-jobs = auto' \
      'trusted-users = root' \
      'compress-build-log = false' \
    >> /etc/nix/nix.conf

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

CMD ["/entrypoint.sh"]
