#!/bin/bash

# Read from file with shared lock
read() {
    local filepath="$1"
    
    exec {fd}<"$filepath" || return 1
    flock -s "$fd"
    cat <&"$fd"
    flock -u "$fd"
    exec {fd}<&-
}

# Write to file with exclusive lock
write() {
    local filepath="$1"
    local data="$2"

    exec {fd}<>"$filepath" || return 1
    flock -x "$fd"
    : > "$fd"
    printf "%s" "$data" >&"$fd"
    flock -u "$fd"
    exec {fd}>&-
}

# Print message to standard output
log() {
    local message="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $message"
}