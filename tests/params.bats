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

@test "direct connect announces the password in force, relay mode none" {
    export GAME_DIR="$TEST_TMP/server"; mkdir -p "$GAME_DIR"
    export PORT=27015

    run game_join_password; [ "$status" -eq 1 ]            # no GameInfo.txt yet

    cp /tests/fixtures/GameInfo.txt "$GAME_DIR/GameInfo.txt"
    run game_join_password; [ "$status" -eq 1 ]            # direct connect, but no password line

    cp /tests/fixtures/GameInfo-direct.txt "$GAME_DIR/GameInfo.txt"
    run game_join_password
    [ "$status" -eq 0 ]; [ "$output" = hunter2 ]           # generated or configured, it is what the file says

    export GAME_PASSWORD=configured-but-ignored
    run game_join_password
    [ "$output" = hunter2 ]                                # the server's word wins over the environment

    unset PORT
    run game_join_password
    [ "$status" -eq 0 ]; [ -z "$output" ]                  # relay mode joins by Game ID: no password
}

@test "direct connect announces the address resolved from SERVER_ADDRESS" {
    export PORT=27015
    corekeeper_resolve4() { echo 203.0.113.9; }

    export SERVER_ADDRESS=corekeeper.example.io:42432
    run game_server_address
    [ "$status" -eq 0 ]; [ "$output" = "203.0.113.9:42432" ]     # host resolved, port kept

    export SERVER_ADDRESS=corekeeper.example.io
    run game_server_address; [ "$output" = "203.0.113.9" ]       # no port, none invented

    export SERVER_ADDRESS=198.51.100.7:42432
    run game_server_address; [ "$output" = "198.51.100.7:42432" ] # already numeric, untouched

    # Unresolvable: report failure so the toolkit warns and announces the
    # configured value rather than a wrong one.
    corekeeper_resolve4() { return 1; }
    export SERVER_ADDRESS=corekeeper.example.io:42432
    run game_server_address
    [ "$status" -eq 1 ]                                          # no address, and it says why
    [[ "$output" == *"cannot resolve corekeeper.example.io"* ]]
    [[ "$output" != *203.0.113.9* ]]

    corekeeper_resolve4() { echo 203.0.113.9; }
    unset SERVER_ADDRESS
    run game_server_address; [ "$status" -eq 2 ]                 # nothing configured

    export SERVER_ADDRESS=corekeeper.example.io:42432; unset PORT
    run game_server_address; [ "$status" -eq 2 ]                 # relay mode: no address of its own
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
    adapter_supports game_join_password
    adapter_supports game_server_address
    [ "$(game_backup_paths)" = world ]
}
