# aarch64-linux Nix builder reachable over SSH.
#
# Determinate's native Linux builder cannot be used: its VM has no network,
# so every fixed-output derivation not already in a cache fails to fetch
# (DeterminateSystems/nix-src#294).
FROM nixos/nix:latest

RUN nix-env -iA nixpkgs.openssh nixpkgs.bash

RUN mkdir -p /etc/nix /root/.ssh /run/sshd \
 && chmod 700 /root/.ssh \
 && printf '%s\n' \
      'experimental-features = nix-command flakes' \
      'sandbox = false' \
      'max-jobs = auto' \
      'trusted-users = root' \
    >> /etc/nix/nix.conf \
 && ssh-keygen -A

# Nix needs a login shell it can exec; the image default is not one.
RUN printf '%s\n' \
      'PermitRootLogin prohibit-password' \
      'PasswordAuthentication no' \
    >> /etc/ssh/sshd_config \
 && echo "root:x:0:0:root:/root:$(command -v bash)" > /etc/passwd

EXPOSE 22
CMD ["/usr/bin/env", "sh", "-c", "exec $(command -v sshd) -D -e"]
