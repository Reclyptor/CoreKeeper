#!/usr/bin/env bats
load test_helper

setup()    { setup_adapter; }
teardown() { teardown_adapter; }

@test "parameters come from the environment in the documented order" {
    export WORLD_NAME="My Cave" WORLD_SEED=42 MAX_PLAYERS=4 GAME_ID=ABCDEFGHIJKLMNOP ACTIVATE_ALL_CONTENT=true
    local -a p; corekeeper_params p
    [[ " ${p[*]} " == *" -batchmode -logfile /dev/stdout "* ]]
    [[ " ${p[*]} " == *" -world 0 -worldname My Cave -worldseed 42 -worldmode 0 -maxplayers 4 "* ]]
    [[ " ${p[*]} " == *" -gameid ABCDEFGHIJKLMNOP -datapath ${DATA_DIR}/world -activateallcontent "* ]]
    [[ " ${p[*]} " != *"-port"* ]]
    [[ " ${p[*]} " != *"-password"* ]]
}

@test "direct-connect parameters only when a port is set" {
    export PORT=27015 BIND=0.0.0.0 GAME_PASSWORD=secret ALLOW_ONLY_PLATFORM=1
    local -a p; corekeeper_params p
    [[ " ${p[*]} " == *" -ip 0.0.0.0 -port 27015 -password secret -allowonlyplatform 1 "* ]]
}

@test "a Game ID is generated once and persisted" {
    unset GAME_ID
    local a b
    a=$(corekeeper_gameid); b=$(corekeeper_gameid)
    [ "$a" = "$b" ]
    corekeeper_valid_gameid "$a"
    [ "$(cat "$DATA_DIR/gameid")" = "$a" ]
}

@test "GAME_ID is validated" {
    export GAME_ID="too-short"
    run corekeeper_gameid
    [ "$status" -eq 1 ]
    export GAME_ID="ValidGameIdentifier01"
    [ "$(corekeeper_gameid)" = ValidGameIdentifier01 ]
}

@test "GameInfo.txt parsing" {
    [ "$(corekeeper_gameinfo /tests/fixtures/GameInfo.txt GameID)" = WRzngFnLmIRcMRdmUcGHfWGhegp2 ]
    [ "$(corekeeper_gameinfo /tests/fixtures/GameInfo-direct.txt GameID)" = SteamOnlyIdentifier123 ]
    [ "$(corekeeper_gameinfo /tests/fixtures/GameInfo-direct.txt Port)" = 27015 ]
    ! corekeeper_gameinfo /nonexistent GameID
}

@test "start command wraps the server in the launcher and clears stale info files" {
    export GAME_DIR="$TEST_TMP/server"; mkdir -p "$GAME_DIR"; touch "$GAME_DIR/GameInfo.txt" "$GAME_DIR/GameID.txt"
    export GAME_ID=ValidGameIdentifier01
    game_start_cmd
    [ "${GAME_CMD[0]}" = bash ]
    [[ "${GAME_CMD[1]}" == */lib/launch.sh ]]
    [ "${GAME_CMD[2]}" = "$GAME_DIR/CoreKeeperServer" ]
    [ ! -e "$GAME_DIR/GameInfo.txt" ]
    [ ! -e "$GAME_DIR/GameID.txt" ]
}

@test "capabilities: no save, broadcast or player query" {
    run game_save;      [ "$status" -eq 2 ]
    run game_broadcast; [ "$status" -eq 2 ]
    run game_players;   [ "$status" -eq 2 ]
    ! adapter_supports game_save
    [ "$(game_backup_paths)" = world ]
}
