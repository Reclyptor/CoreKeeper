#!/usr/bin/env bash
# End-to-end against the real game: SteamCMD install (slow: ~1–2 GB) → session
# up → Game ID announced → backup holds the world → update check → SIGTERM,
# reporting whether the world was written on the way down → direct connect,
# where START must carry the address resolved from SERVER_ADDRESS (the join
# field cannot resolve names) and the join password in force, generated first
# and then configured.
set -euo pipefail
cd "$(dirname "$0")/.."

: "${GAME_IMAGE:=corekeeper:test}"
runner="${GAME_IMAGE}-runner"
name=corekeeper-smoke-$$
net="${name}-net"
hooks_ctr="${name}-hooks"
hook_port=18089
work=$(mktemp -d)
hooks="$work/webhooks.log"

cleanup() {
    docker rm -f "$name" "$hooks_ctr" >/dev/null 2>&1 || true
    docker volume rm "${name}-data" >/dev/null 2>&1 || true
    docker network rm "$net" >/dev/null 2>&1 || true
    rm -rf "$work"
}
trap cleanup EXIT

fail() {
    echo "SMOKE FAIL: $*" >&2
    echo "--- container log ---" >&2; docker logs "$name" 2>&1 | tail -80 >&2 || true
    echo "--- webhooks ---" >&2; sync_hooks; cat "$hooks" >&2
    exit 1
}
step() { echo "==> $*"; }
sync_hooks() { docker logs "$hooks_ctr" 2>/dev/null > "$hooks" || true; }
wait_for() {
    local what=$1 pattern=$2 timeout=${3:-60} i
    for (( i = 0; i < timeout; i++ )); do
        sync_hooks; grep -cE "$pattern" "$hooks" >/dev/null && return 0; sleep 1
    done
    fail "timed out waiting for ${what}: /${pattern}/"
}
in_game() { docker exec "$name" bash -c "source /opt/gameops/shim/adapter.sh; adapter_load; $*"; }

step "build images"
[[ -n "$(docker images -q "$GAME_IMAGE")" ]] || docker build -q -t "$GAME_IMAGE" . >/dev/null
docker build -q -t "$runner" --build-arg "GAME_IMAGE=${GAME_IMAGE}" -f tests/runner.Dockerfile tests >/dev/null

step "start webhook receiver"
docker network create "$net" >/dev/null
docker run -d --name "$hooks_ctr" --network "$net" --entrypoint python3 "$runner" -u -c "
import http.server
class H(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        body = self.rfile.read(int(self.headers.get('Content-Length', 0))).decode()
        print(body, flush=True)
        self.send_response(204); self.end_headers()
    def log_message(self, *a): pass
http.server.HTTPServer(('0.0.0.0', ${hook_port}), H).serve_forever()
" >/dev/null
sleep 1

step "run core keeper (SteamCMD install on first boot)"
docker volume create "${name}-data" >/dev/null
docker run -d --name "$name" --network "$net" -v "${name}-data:/data" \
    -e "DISCORD_WEBHOOK_URL=http://${hooks_ctr}:${hook_port}/hook" \
    -e SERVER_NAME=Smoke -e WORLD_NAME="Smoke World" -e MAX_PLAYERS=3 -e UPDATE_ON_BOOT=false \
    -e STOP_TIMEOUT=60 -e BACKUP_RETAIN_DAYS=0 -e LOG_LEVEL=debug -e READY_TIMEOUT=600 \
    "$GAME_IMAGE" >/dev/null
wait_for "START notification" 'Smoke server is online' 1800
wait_for "GAMEID notification" 'Game ID: [A-Za-z0-9]{15,28}' 60
gameid=$(sync_hooks; grep -oE 'Game ID: [A-Za-z0-9]+' "$hooks" | head -1 | cut -d' ' -f3)
echo "    game id: ${gameid}"
[[ "$(docker exec "$name" cat /data/gameid)" == "$gameid" ]] || fail "persisted Game ID differs from the announced one"
docker exec "$name" grep -c "GameID: ${gameid}" /data/server/GameInfo.txt >/dev/null || fail "GameInfo.txt lacks the Game ID"

step "health"
for i in $(seq 1 12); do
    [[ "$(docker inspect -f '{{.State.Health.Status}}' "$name")" == healthy ]] && break
    sleep 5
done
[[ "$(docker inspect -f '{{.State.Health.Status}}' "$name")" == healthy ]] || fail "container health is $(docker inspect -f '{{.State.Health.Status}}' "$name")"
[[ "$(in_game 'game_version')" =~ ^[0-9]+$ ]] || fail "game_version is not a build id"
echo "    build id: $(in_game 'game_version')"
echo "    world files: $(docker exec "$name" sh -c 'ls /data/world' | tr '\n' ' ')"

step "backup"
docker exec "$name" gameops backup
wait_for "BACKUP_POST notification" 'Manual backup of the Smoke server complete: /backups/corekeeper-' 90
archive=$(docker exec "$name" sh -c 'ls /backups/corekeeper-*.tar.gz')
docker exec "$name" tar -tzf "$archive" | grep -c '^world/' >/dev/null || fail "archive lacks the world dir"

step "update check against Steam"
out=$(in_game 'game_update_available; echo "rc=$?"')
echo "    check → ${out##*$'\n'}"
[[ "$out" == *"rc=1"* ]] || fail "just installed, so the check must report current: ${out}"

step "graceful stop on SIGTERM"
before=$(docker exec "$name" sh -c 'find /data/world -type f -printf "%T@\n" | sort -n | tail -1 | cut -d. -f1')
before=${before:-0}
sleep 2
docker stop -t 90 "$name" >/dev/null
code=$(docker inspect -f '{{.State.ExitCode}}' "$name")
[[ "$code" == 0 ]] || fail "expected exit 0 after SIGTERM, got ${code}"
wait_for "STOP notification" 'Smoke server has shut down' 10
after=$(docker run --rm -v "${name}-data:/data" --entrypoint sh "$GAME_IMAGE" -c 'find /data/world -type f -printf "%T@\n" | sort -n | tail -1 | cut -d. -f1')
after=${after:-0}
if (( after > before )); then
    echo "    SIGTERM-SAVE: yes (world mtime ${before} → ${after})"
else
    echo "    SIGTERM-SAVE: NO (world mtime ${before} → ${after}) — the server did not flush on SIGTERM"
fi
docker logs "$name" 2>&1 | grep -cE 'Smoke has shut down|stop requested' >/dev/null || true

# Direct connections always take a password: the configured one, or one the
# server generates when it is given none. START must announce whichever is in
# force. Same volume, so the install is already there.
direct_env=(
    --network "$net" -v "${name}-data:/data"
    -e "DISCORD_WEBHOOK_URL=http://${hooks_ctr}:${hook_port}/hook"
    -e WORLD_NAME="Smoke World" -e MAX_PLAYERS=3 -e UPDATE_ON_BOOT=false -e STOP_TIMEOUT=60
    -e BACKUP_ENABLED=false -e UPDATE_ENABLED=false -e LOG_LEVEL=debug -e READY_TIMEOUT=600
    -e PORT=27015
    # A host name the server can really resolve inside the docker network, so
    # the announced address can be checked against what it resolves to.
    -e "SERVER_ADDRESS=${hooks_ctr}:42432"
)
# password_in_force → the Password: line of GameInfo.txt
password_in_force() { docker exec "$name" sed -n 's/^Password: *//p' /data/server/GameInfo.txt; }

step "direct connect without a password announces the one the server generated"
docker rm -f "$name" >/dev/null
docker run -d --name "$name" "${direct_env[@]}" -e SERVER_NAME=Generated "$GAME_IMAGE" >/dev/null
wait_for "START with a password" "Generated server is online[^\"]*\\(password: \`[^\`]+\`\\)" 600
generated=$(password_in_force)
[[ -n "$generated" ]] || fail "GameInfo.txt names no password in direct-connect mode"
echo "    generated password: ${generated}"
# The join field cannot resolve names, so START must carry the resolved IPv4.
receiver_ip=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$hooks_ctr")
sync_hooks
grep -qF "connect to \`${receiver_ip}:42432\`" "$hooks" || fail "START did not announce the resolved address (${receiver_ip}:42432)"
grep -qF "connect to \`${hooks_ctr}:42432\`" "$hooks" && fail "START announced the unresolvable host name instead of its address"
echo "    announced address: ${receiver_ip}:42432 (resolved from ${hooks_ctr})"
sync_hooks; grep -qF "(password: \`${generated}\`)" "$hooks" || fail "START did not announce the password the server generated (${generated})"
docker stop -t 90 "$name" >/dev/null

step "direct connect with GAME_PASSWORD enforces and announces it"
docker rm -f "$name" >/dev/null
docker run -d --name "$name" "${direct_env[@]}" -e SERVER_NAME=Configured -e GAME_PASSWORD=smoke-pass "$GAME_IMAGE" >/dev/null
wait_for "START with the configured password" "Configured server is online[^\"]*\\(password: \`smoke-pass\`\\)" 600
[[ "$(password_in_force)" == smoke-pass ]] || fail "the server does not enforce GAME_PASSWORD (GameInfo.txt says '$(password_in_force)')"
docker stop -t 90 "$name" >/dev/null

echo "SMOKE OK"
