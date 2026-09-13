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

corekeeper_relay_mode() { [[ -z "${PORT:-}" ]]; }

# Ready once the session is up and GameInfo.txt is written: that file is how
# players learn to join (the Game ID, or the address and password), so nothing
# is announced before it exists. In relay mode the Game ID is announced the
# first time it is seen after each launch.
game_ready() {
    grep -c 'Started session with info' "$(corekeeper_log)" >/dev/null 2>&1 || return 1
    local info="${GAME_DIR}/GameInfo.txt" id
    [[ -s "$info" ]] || return 1
    if corekeeper_relay_mode && ! flag_is_set gameid.notified; then
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

# The game's "join via IP" field does not resolve host names — it sends the text
# straight at DNS with "www." glued on the front, which resolves to nothing — so
# players need the address as a literal IPv4. SERVER_ADDRESS stays the tunnel's
# host name (one source of truth, and the tunnel provider keeps owning the
# address); this resolves it fresh at every launch, so the announced address can
# never drift from the record. Already-numeric addresses pass through untouched;
# relay mode joins by Game ID, where the address means nothing.
corekeeper_resolve4() { getent ahostsv4 "$1" | awk 'NR==1{print $1}'; }

game_server_address() {
    corekeeper_relay_mode && return 2
    local addr=${SERVER_ADDRESS:-}
    [[ -n "$addr" ]] || return 2
    local host=${addr%:*} port=""
    [[ "$addr" == *:* ]] && port=${addr##*:}
    [[ "$host" =~ ^[0-9]+(\.[0-9]+){3}$ ]] && { printf '%s' "$addr"; return 0; }
    local ip
    ip=$(corekeeper_resolve4 "$host") || true
    [[ -n "$ip" ]] || { log_warn "cannot resolve ${host}; announcing SERVER_ADDRESS as configured"; return 1; }
    printf '%s' "${ip}${port:+:$port}"
}

# Direct connections always take a password: GAME_PASSWORD, or one the server
# generates when that is empty or invalid. GameInfo.txt names the one in force,
# which is what START must announce. Relay mode joins by Game ID and takes none.
# A direct-connect server whose GameInfo.txt names no password is reported as a
# failure, so the toolkit warns instead of announcing that there is none.
game_join_password() {
    corekeeper_relay_mode && return 0
    local password
    password=$(corekeeper_gameinfo "${GAME_DIR}/GameInfo.txt" Password) || return 1
    [[ -n "$password" ]] || return 1
    printf '%s' "$password"
}

# ── control: none ───────────────────────────────────────────────────────────

game_save()      { return 2; }
game_broadcast() { return 2; }
game_players()   { return 2; }

# ── events ──────────────────────────────────────────────────────────────────

game_events() { follow_log "$(corekeeper_log)" | corekeeper_parse_events; }

# ── backups ─────────────────────────────────────────────────────────────────

game_backup_paths() { echo world; }
