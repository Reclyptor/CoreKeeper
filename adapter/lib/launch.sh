#!/usr/bin/env bash
# Launch wrapper: bring up the virtual display, run the server in the
# foreground, forward SIGTERM to it, tear the display down, exit with the
# server's code. The toolkit treats this wrapper as "the server process".
set -uo pipefail

: "${DISPLAY_NUMBER:=:99}"
lock="/tmp/.X${DISPLAY_NUMBER#:}-lock"
rm -f "$lock" "/tmp/.X11-unix/X${DISPLAY_NUMBER#:}"

Xvfb "$DISPLAY_NUMBER" -screen 0 1x1x24 -nolisten tcp >/dev/null 2>&1 &
xvfb_pid=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do
    [[ -e "/tmp/.X11-unix/X${DISPLAY_NUMBER#:}" ]] && break
    sleep 0.5
done

export DISPLAY="$DISPLAY_NUMBER"
export LD_LIBRARY_PATH="${STEAMCMD_DIR:-/home/steam/steamcmd}/linux64:${LD_LIBRARY_PATH:-}"

"$@" &
server_pid=$!

# shellcheck disable=SC2317,SC2329  # invoked by the trap (code differs by shellcheck version)
forward() { kill -TERM "$server_pid" 2>/dev/null; }
trap forward TERM INT

rc=0
while kill -0 "$server_pid" 2>/dev/null; do
    wait "$server_pid"
    rc=$?
done

kill "$xvfb_pid" 2>/dev/null
wait "$xvfb_pid" 2>/dev/null
rm -f "$lock"
exit "$rc"
