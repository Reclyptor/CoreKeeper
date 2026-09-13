#!/usr/bin/env bash
# GameOps adapter for Core Keeper — the game with no control channel: no RCON,
# no REST, no console. Everything the toolkit learns comes from the log and
# GameInfo.txt; everything it does to the server is a signal.
# Contract: https://github.com/Reclyptor/GameOps/blob/master/docs/CONTRACT.md
# shellcheck shell=bash
# shellcheck disable=SC2034  # GAME_* and GAME_CMD are consumed by the toolkit

GAME_NAME=corekeeper
GAME_DIR=${GAME_DIR:-${DATA_DIR}/server}
# Relay mode (the default, PORT unset) has no inbound port. Direct-connect mode
# (PORT set) is UDP, which the toolkit's health check does not probe either.
GAME_PORT=${PORT:-}
GAME_PORT_PROTO=udp
: "${LOGFILE:=/dev/stdout}"

APP_STEAMWORKS=1007
APP_SERVER=1963720
DEPOT_LINUX=1963722

# Relay mode only: the Game ID is how players join, so it is announced after
# every launch. In direct-connect mode (PORT) the START message
# already carries the address, and the Game ID means nothing to players.
: "${DISCORD_GAMEID_MESSAGE:=🎮 server_name server Game ID: game_id}"
export DISCORD_GAMEID_MESSAGE

ADAPTER_DIR=$(dirname "${BASH_SOURCE[0]}")
# shellcheck source=adapter/lib/params.sh
source "${ADAPTER_DIR}/lib/params.sh"
# shellcheck source=adapter/lib/events.sh
source "${ADAPTER_DIR}/lib/events.sh"

# Where the server writes its log: the console log (via -logfile /dev/stdout,
# the default) or a file of the operator's choosing.
corekeeper_log() {
    if [[ "$LOGFILE" == /dev/stdout ]]; then printf '%s' "$GAME_LOG"; else printf '%s' "$LOGFILE"; fi
}

# ── install / version / update ──────────────────────────────────────────────

game_install() {
    mkdir -p "$GAME_DIR" "${DATA_DIR}/world" "${DATA_DIR}/logs"
    if [[ ! -x "${GAME_DIR}/CoreKeeperServer" ]]; then
        log_action "installing Core Keeper dedicated server via SteamCMD"
        steam_install "$GAME_DIR" "$APP_STEAMWORKS" "$APP_SERVER" || return 1
    fi
    [[ -x "${GAME_DIR}/CoreKeeperServer" ]] || chmod +x "${GAME_DIR}/CoreKeeperServer"
    corekeeper_gameid >/dev/null
}

game_version() { corekeeper_installed_build || echo unknown; }

game_update_available() { steam_update_available "$GAME_DIR" "$APP_SERVER" "$DEPOT_LINUX"; }

game_update_apply() { steam_install "$GAME_DIR" "$APP_STEAMWORKS" "$APP_SERVER"; }

# ── process ─────────────────────────────────────────────────────────────────

game_start_cmd() {
    local -a params=()
    corekeeper_params params || return 1
    rm -f "${GAME_DIR}/GameID.txt" "${GAME_DIR}/GameInfo.txt"
    flag_clear gameid.notified
    GAME_CMD=(bash "${ADAPTER_DIR}/lib/launch.sh" "${GAME_DIR}/CoreKeeperServer" "${params[@]}")
}

# Ready once the session is up. In relay mode the Game ID is announced the
# first time GameInfo.txt is seen after each launch.
corekeeper_relay_mode() { [[ -z "${PORT:-}" ]]; }

game_ready() {
    grep -c 'Started session with info' "$(corekeeper_log)" >/dev/null 2>&1 || return 1
    local info="${GAME_DIR}/GameInfo.txt" id
    if corekeeper_relay_mode && ! flag_is_set gameid.notified && [[ -r "$info" ]]; then
        id=$(corekeeper_gameinfo "$info" GameID)
        if [[ -n "$id" ]]; then
            flag_set gameid.notified
            log_info "Game ID: ${id}"
            notify GAMEID "game_id=${id}"
        fi
    fi
    return 0
}

game_healthy() {
    server_pid >/dev/null || return 1
    [[ -f "${GAME_DIR}/GameInfo.txt" ]]
}

# game_shutdown: the default (SIGTERM, forwarded by launch.sh) — see SPEC.md §4.

# ── control: none ───────────────────────────────────────────────────────────

game_save()      { return 2; }
game_broadcast() { return 2; }
game_players()   { return 2; }

# ── events ──────────────────────────────────────────────────────────────────

game_events() { follow_log "$(corekeeper_log)" | corekeeper_parse_events; }

# ── backups ─────────────────────────────────────────────────────────────────

game_backup_paths() { echo world; }
