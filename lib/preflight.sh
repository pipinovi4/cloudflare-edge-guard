#!/usr/bin/env bash

set -Eeuo pipefail

preflight_base() {
    [[ "${EDGE_GUARD_ALLOW_NON_ROOT:-false}" == true || "$EUID" -eq 0 ]] || die "Run as root (or use --dry-run for inspection)"
    case "$(uname -s)" in Linux) ;; *) die "Only Linux is supported" ;; esac
    require_command awk
    require_command install
    require_command sha256sum
}

check_upstream() {
    require_command curl
    curl --fail --silent --show-error --max-time 5 "http://${UPSTREAM_HOST}:${UPSTREAM_PORT}${HEALTHCHECK_PATH}" >/dev/null ||
        die "Upstream health check failed"
}

check_domain() {
    require_command getent
    local resolved
    resolved="$(getent ahosts "$DOMAIN" 2>/dev/null | awk '{print $1}' | sort -u)"
    [[ -n "$resolved" ]] || die "Domain does not resolve: $DOMAIN"
    info "Domain resolves; Cloudflare proxy status must also be confirmed in the dashboard"
}
