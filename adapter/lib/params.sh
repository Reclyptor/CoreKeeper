#!/usr/bin/env bash
# Launch parameters, Game ID handling and GameInfo.txt parsing.
# shellcheck shell=bash

# A valid Game ID is 15–28 alphanumeric characters.
corekeeper_valid_gameid() { [[ "$1" =~ ^[A-Za-z0-9]{15,28}$ ]]; }

corekeeper_generate_gameid() {
    head -c 64 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 20
}

# The Game ID players join with. GAME_ID wins; otherwise one is generated
# once and kept in <data>/gameid so it survives restarts and updates.
corekeeper_gameid() {
    local file="${DATA_DIR}/gameid" id
    if [[ -n "${GAME_ID:-}" ]]; then
        corekeeper_valid_gameid "$GAME_ID" || { log_error "GAME_ID must be 15–28 alphanumeric characters"; return 1; }
        printf '%s' "$GAME_ID"
        return 0
    fi
    if [[ -r "$file" ]]; then
        id=$(<"$file")
        corekeeper_valid_gameid "$id" && { printf '%s' "$id"; return 0; }
        log_warn "ignoring invalid Game ID in ${file}"
    fi
    id=$(corekeeper_generate_gameid)
    printf '%s' "$id" > "$file"
    log_info "generated Game ID ${id} (kept in ${file})"
    printf '%s' "$id"
}

# Populate the array named by $1 with the server's command-line parameters.
corekeeper_params() {
    local -n out=$1
    local gameid
    gameid=$(corekeeper_gameid) || return 1
    out=(-batchmode -logfile "${LOGFILE:-/dev/stdout}")
    local spec flag var v
    for spec in "-world:WORLD_INDEX" "-worldname:WORLD_NAME" "-worldseed:WORLD_SEED" \
             "-worldmode:WORLD_MODE" "-hashedworldseed:HASHED_WORLD_SEED" "-maxplayers:MAX_PLAYERS" \
             "-season:SEASON" "-ip:BIND" "-port:PORT" "-activatecontent:ACTIVATE_CONTENT" \
             "-password:GAME_PASSWORD" "-allowonlyplatform:ALLOW_ONLY_PLATFORM"; do
        flag=${spec%%:*}; var=${spec#*:}; v=${!var:-}
        [[ -n "$v" ]] && out+=("$flag" "$v")
    done
    out+=(-gameid "$gameid" -datapath "${DATA_DIR}/world")
    is_true "${ACTIVATE_ALL_CONTENT:-false}" && out+=(-activateallcontent)
    return 0
}

# GameInfo.txt is written next to the executable once the session is up:
#   GameID: <id>            (or "Steam GameID: <id>")
#   Public IP: ... Port: ... Password: ...   (direct-connect mode only)
corekeeper_gameinfo() {
    local file=$1 key=$2
    [[ -r "$file" ]] || return 1
    sed -n "s/^\(Steam \)\?${key}: *//p" "$file" | head -1
}
