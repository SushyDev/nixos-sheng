#!/bin/sh
# Keep the container alive and stream build logs to `docker logs`. Builds are
# started with `docker exec`, so their output never reaches PID 1; these come
# from /nix/var/log/nix/drvs instead, kept plain by compress-build-log = false.
set -e

readonly DRV_LOGS=/nix/var/log/nix/drvs
readonly SEEN=/tmp/tailed-logs

mkdir -p "$DRV_LOGS"
: >"$SEEN"

echo "sheng-builder ready; streaming build logs from $DRV_LOGS"

while :; do
  # Skip .bz2: logs from before compress-build-log was turned off.
  find "$DRV_LOGS" -type f ! -name '*.bz2' 2>/dev/null | while read -r log; do
    grep -qxF "$log" "$SEEN" && continue
    echo "$log" >>"$SEEN"
    echo "=== $(basename "$log") ==="
    tail -F -n +1 "$log" &
  done
  sleep 2
done
