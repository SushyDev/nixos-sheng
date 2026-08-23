#!/bin/sh
# Run sshd, and stream build logs to stdout so they show up in `docker
# logs` and the OrbStack UI.
#
# Remote builds arrive over ssh, so their output goes to that session,
# not to PID 1. Nix also writes each build's log under
# /nix/var/log/nix/drvs; compress-build-log is off so those stay plain
# text and can be tailed.
set -e

readonly DRV_LOGS=/nix/var/log/nix/drvs
readonly SEEN=/tmp/tailed-logs

mkdir -p "$DRV_LOGS"
: >"$SEEN"

sshd -D -e &

echo "sheng-builder ready; streaming build logs from $DRV_LOGS"

while :; do
  find "$DRV_LOGS" -type f 2>/dev/null | while read -r log; do
    grep -qxF "$log" "$SEEN" && continue
    echo "$log" >>"$SEEN"
    echo "=== $(basename "$log") ==="
    tail -F -n +1 "$log" &
  done
  sleep 2
done
