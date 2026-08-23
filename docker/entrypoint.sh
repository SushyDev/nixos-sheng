#!/bin/sh
# Keep the container alive and stream build logs to stdout, so they show
# up in `docker logs` and the OrbStack UI.
#
# Builds are started with `docker exec`, so their output goes to that
# session rather than PID 1. Nix also writes each build's log under
# /nix/var/log/nix/drvs; compress-build-log is off so those stay plain
# text and can be tailed.
set -e

readonly DRV_LOGS=/nix/var/log/nix/drvs
readonly SEEN=/tmp/tailed-logs

mkdir -p "$DRV_LOGS"
: >"$SEEN"

echo "sheng-builder ready; streaming build logs from $DRV_LOGS"

while :; do
  # Skip .bz2: logs written before compress-build-log was turned off are
  # compressed, and dumping them to stdout is line noise.
  find "$DRV_LOGS" -type f ! -name '*.bz2' 2>/dev/null | while read -r log; do
    grep -qxF "$log" "$SEEN" && continue
    echo "$log" >>"$SEEN"
    echo "=== $(basename "$log") ==="
    tail -F -n +1 "$log" &
  done
  sleep 2
done
