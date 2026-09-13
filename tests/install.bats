#!/usr/bin/env bats
load test_helper

setup()    { setup_adapter; }
teardown() { teardown_adapter; }

@test "the build id is read from the app manifest" {
    export GAME_DIR="$TEST_TMP/server"; mkdir -p "$GAME_DIR/steamapps"
    [ "$(game_version)" = unknown ]
    cp /tests/fixtures/appmanifest_1963720.acf "$GAME_DIR/steamapps/"
    [ "$(game_version)" = 23543502 ]
}

@test "update detection defers to the toolkit's Steam manifest check" {
    export GAME_DIR="$TEST_TMP/server"
    steam_update_available() { printf '%s %s %s\n' "$@" > "$TEST_TMP/steam-args"; return 1; }
    run game_update_available; [ "$status" -eq 1 ]
    [ "$(cat "$TEST_TMP/steam-args")" = "$GAME_DIR 1963720 1963722" ]
    steam_update_available() { echo 111; return 0; }
    run game_update_available; [ "$status" -eq 0 ]; [ "$output" = 111 ]
}

@test "game_install calls SteamCMD only when the binary is absent" {
    export GAME_DIR="$TEST_TMP/server" GAME_ID=ValidGameIdentifier01
    steam_install() { printf '%s\n' "$@" > "$TEST_TMP/args"; mkdir -p "$1" && touch "$1/CoreKeeperServer"; }
    game_install
    [ "$(tr '\n' ' ' < "$TEST_TMP/args")" = "$GAME_DIR 1007 1963720 " ]
    rm "$TEST_TMP/args"
    game_install
    [ ! -e "$TEST_TMP/args" ]
}
