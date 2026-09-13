#!/usr/bin/env bash
# Shared bats setup: source the toolkit shim and the adapter against a
# throwaway DATA_DIR. Notifications and network calls are stubbed by
# overriding the shim's functions after sourcing.
# shellcheck shell=bash
# shellcheck disable=SC2034

setup_adapter() {
    TEST_TMP=$(mktemp -d)
    export GAMEOPS_HOME=/opt/gameops
    export GAMEOPS_STATE="$TEST_TMP/state"
    export DATA_DIR="$TEST_TMP/data"
    export BACKUP_DIR="$TEST_TMP/backups"
    export GAME_ADAPTER=/opt/game/adapter.sh
    export LOG_LEVEL=warn
    mkdir -p "$GAMEOPS_STATE" "$DATA_DIR" "$BACKUP_DIR"

    export NOTIFY_LOG="$TEST_TMP/notify.log"
    : > "$NOTIFY_LOG"

    # shellcheck source=/dev/null
    source "${GAMEOPS_HOME}/shim/adapter.sh"
    adapter_load

    # Record notifications instead of sending them: "<EVENT> key=value ..."
    # shellcheck disable=SC2317,SC2329  # invoked by the adapter under test
    notify() { printf '%s\n' "$*" >> "$NOTIFY_LOG"; }
}

teardown_adapter() { rm -rf "$TEST_TMP"; }

fixture() { cat "/tests/fixtures/$1"; }
