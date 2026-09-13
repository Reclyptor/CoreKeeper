#!/usr/bin/env bats
load test_helper

setup()    { setup_adapter; }
teardown() { teardown_adapter; }

@test "log lines become JOIN/LEAVE with names resolved from the user id" {
    run corekeeper_parse_events "$TEST_TMP/map" < /tests/fixtures/server.log
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "JOIN Alice" ]
    [ "${lines[1]}" = "JOIN Bob Builder" ]
    [ "${lines[2]}" = "LEAVE Alice" ]
    [ "${lines[3]}" = "LEAVE Bob Builder" ]
    [ "${lines[4]}" = "LEAVE userid:99" ]
    [ "${#lines[@]}" -eq 5 ]
}

@test "direct-connect mode is ready without announcing the Game ID" {
    export GAME_DIR="$TEST_TMP/server" PORT=27015; mkdir -p "$GAME_DIR" "$(dirname "$GAME_LOG")"
    echo "Started session with info: x" > "$GAME_LOG"
    cp /tests/fixtures/GameInfo.txt "$GAME_DIR/GameInfo.txt"
    game_ready
    [ ! -s "$NOTIFY_LOG" ]
}

@test "relay mode needs the session line, then announces the Game ID once" {
    export GAME_DIR="$TEST_TMP/server"; mkdir -p "$GAME_DIR" "$(dirname "$GAME_LOG")"
    : > "$GAME_LOG"
    run game_ready; [ "$status" -eq 1 ]
    echo "Started session with info: x" >> "$GAME_LOG"
    cp /tests/fixtures/GameInfo.txt "$GAME_DIR/GameInfo.txt"
    game_ready
    [ "$(cat "$NOTIFY_LOG")" = "GAMEID game_id=WRzngFnLmIRcMRdmUcGHfWGhegp2" ]
    game_ready
    [ "$(grep -c 'GAMEID' "$NOTIFY_LOG")" -eq 1 ]
}

@test "health needs a live process and GameInfo.txt" {
    export GAME_DIR="$TEST_TMP/server"; mkdir -p "$GAME_DIR"
    run game_healthy; [ "$status" -eq 1 ]
    sleep 30 & printf '%s' $! > "$(state_file server.pid)"
    run game_healthy; [ "$status" -eq 1 ]
    touch "$GAME_DIR/GameInfo.txt"
    run game_healthy; [ "$status" -eq 0 ]
    kill %1 2>/dev/null || true
}
