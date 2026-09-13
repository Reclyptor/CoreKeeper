#!/usr/bin/env bash
# Player events from the server log. Joins carry the character name; leaves
# only the user id, so a small id→name map is kept per launch.
# shellcheck shell=bash

# Reads log lines on stdin, emits "JOIN <name>" / "LEAVE <name>".
#   [userid:76561198000000000] player Alice connected islocalplayer=False
#   Disconnected from userid: 76561198000000000 with reason ClientDisconnect
corekeeper_parse_events() {
    local map=${1:-$(state_file ck-players)} line id name
    : > "$map"
    while IFS= read -r line; do
        if [[ "$line" =~ \[userid:([0-9]+)\]\ player\ (.+)\ connected\ islocalplayer= ]]; then
            id=${BASH_REMATCH[1]}; name=${BASH_REMATCH[2]}
            printf '%s\t%s\n' "$id" "$name" >> "$map"
            printf 'JOIN %s\n' "$name"
        elif [[ "$line" =~ Disconnected\ from\ userid:\ ?([0-9]+) ]]; then
            id=${BASH_REMATCH[1]}
            name=$(awk -F'\t' -v id="$id" '$1 == id { n = $2 } END { print n }' "$map")
            printf 'LEAVE %s\n' "${name:-userid:${id}}"
        fi
    done
}

# The current build id from SteamCMD's app manifest.
corekeeper_installed_build() {
    local acf="${GAME_DIR}/steamapps/appmanifest_1963720.acf"
    [[ -r "$acf" ]] || return 1
    awk '$1 == "\"buildid\"" { gsub(/"/, "", $2); print $2; exit }' "$acf"
}
