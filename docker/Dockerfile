# aarch64-linux Nix builder reachable over SSH.
#
# Determinate's native Linux builder cannot be used: its VM has no
# network, so fixed-output derivations that are not already in a cache
# fail to fetch (DeterminateSystems/nix-src#294).
FROM nixos/nix:latest

RUN nix-env -iA nixpkgs.openssh nixpkgs.bash

ENV PATH=/root/.nix-profile/bin:/usr/bin:/bin

RUN printf '%s\n' \
      'experimental-features = nix-command flakes' \
      'sandbox = false' \
      'max-jobs = auto' \
      'trusted-users = root' \
      'compress-build-log = false' \
    >> /etc/nix/nix.conf

# The account files are symlinks into /nix/store, and the named volume on
# /nix shadows them with whatever it was seeded from. Replace them with
# real files or later image changes silently fail to apply at runtime.
#
# root ships locked and sshd refuses a locked account even for key auth.
# sshd also needs its privilege-separation user.
RUN cp -L /etc/passwd /tmp/passwd && rm -f /etc/passwd && mv /tmp/passwd /etc/passwd \
 && cp -L /etc/group /tmp/group && rm -f /etc/group && mv /tmp/group /etc/group \
 && echo 'sshd:x:74:74:sshd:/var/empty:/sbin/nologin' >> /etc/passwd \
 && echo 'sshd:x:74:' >> /etc/group \
 && printf 'root:*:19000:0:99999:7:::\nsshd:!:19000:0:99999:7:::\n' > /etc/shadow \
 && chmod 600 /etc/shadow

# /etc/ssh and /run do not exist in the base image. StrictModes off: the
# authorized_keys file is bind-mounted from the host and will not be
# root-owned. SetEnv: sshd sessions do not inherit the image ENV, and the
# remote builder needs nix-store on PATH.
RUN mkdir -p /root/.ssh /var/empty /etc/ssh /run \
 && chmod 700 /root/.ssh \
 && ssh-keygen -A \
 && printf '%s\n' \
      'PermitRootLogin prohibit-password' \
      'PasswordAuthentication no' \
      'StrictModes no' \
      'SetEnv PATH=/root/.nix-profile/bin:/nix/var/nix/profiles/default/bin:/usr/bin:/bin' \
    >> /etc/ssh/sshd_config

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 22
CMD ["/entrypoint.sh"]
