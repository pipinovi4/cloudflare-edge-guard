#!/usr/bin/env bash

set -Eeuo pipefail

EDGE_GUARD_ROOT="${EDGE_GUARD_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
DRY_RUN="${DRY_RUN:-false}"
VERBOSE="${VERBOSE:-false}"

log() {
    local level="$1"
    shift
    local line
    line="$(date -u +'%Y-%m-%dT%H:%M:%SZ') [$level] $*"
    printf '%s\n' "$line" >&2
    if [[ -n "${LOG_FILE:-}" && "$DRY_RUN" != true ]]; then
        printf '%s\n' "$line" >>"$LOG_FILE" 2>/dev/null || true
    fi
}

info() { log INFO "$@"; }
warn() { log WARN "$@"; }
die() {
    log ERROR "$@"
    exit 1
}
debug() {
    if [[ "$VERBOSE" == true ]]; then
        log DEBUG "$@"
    fi
}

run() {
    if [[ "$DRY_RUN" == true ]]; then
        printf '[dry-run]'
        printf ' %q' "$@"
        printf '\n'
        return 0
    fi
    debug "run: $(printf '%q ' "$@")"
    "$@"
}

require_command() { command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"; }

ensure_dir() {
    local path="$1" mode="${2:-0750}"
    [[ -d "$path" ]] || run install -d -m "$mode" "$path"
}

backup_file() {
    local source="$1"
    [[ -e "$source" || -L "$source" ]] || return 0
    ensure_dir "$BACKUP_DIR"
    local target
    target="$BACKUP_DIR/$(basename "$source").$(date -u +%Y%m%dT%H%M%SZ).bak"
    run cp -a -- "$source" "$target"
    info "Backup created: $target"
}

install_if_changed() {
    local source="$1" target="$2" mode="${3:-0644}"
    if [[ -f "$target" ]] && cmp -s "$source" "$target"; then
        info "Unchanged: $target"
        return 1
    fi
    backup_file "$target"
    run install -m "$mode" "$source" "$target"
    info "Updated: $target"
    return 0
}

with_lock() {
    local lock_file="$1"
    shift
    if [[ "$DRY_RUN" == true ]]; then
        "$@"
        return
    fi
    require_command flock
    ensure_dir "$(dirname "$lock_file")"
    exec 9>"$lock_file"
    flock -n 9 || die "Another edge-guard operation is already running"
    "$@"
}
