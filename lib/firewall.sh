#!/usr/bin/env bash

set -Eeuo pipefail

ufw_active() { ufw status 2>/dev/null | grep -q '^Status: active'; }

managed_rule_numbers() {
    local keep_digest="${1:-}"
    ufw status numbered 2>/dev/null | awk -v keep="$keep_digest" '
        /cloudflare-edge-guard:/ && (keep == "" || index($0, "cloudflare-edge-guard:" keep) == 0) {
            number=$1; gsub(/[^0-9]/, "", number); print number
        }' | sort -rn
}

rule_exists() {
    local cidr="$1" port="$2" comment="$3"
    ufw status 2>/dev/null | grep -F "$cidr" | grep -F "$port/tcp" | grep -Fq "$comment"
}

delete_managed_digest() {
    local digest="$1" number
    while IFS= read -r number; do [[ -n "$number" ]] && run ufw --force delete "$number"; done < <(managed_rule_numbers "$digest")
}

apply_firewall() {
    local ranges="$1" digest comment cidr port added=() number
    [[ "$ENABLE_UFW" == true && "$ENABLE_CLOUDFLARE_EDGE_GUARD" == true ]] || return 0
    require_command ufw
    ufw_active || die "UFW must already be enabled; edge-guard will not enable it automatically"
    digest="$(ranges_digest "$ranges")"
    comment="cloudflare-edge-guard:$digest"
    # New rules are installed before old managed rules are removed. Any failure
    # deletes only the new digest, leaving SSH, unrelated, and old rules intact.
    # ShellCheck cannot see trap-based calls to this local rollback handler.
    # shellcheck disable=SC2317
    firewall_rollback() {
        # shellcheck disable=SC2317
        warn "Firewall update failed; rolling back newly added managed rules"
        # shellcheck disable=SC2317
        local rollback_number
        # shellcheck disable=SC2317
        while IFS= read -r rollback_number; do
            if [[ -n "$rollback_number" ]]; then
                ufw --force delete "$rollback_number" >/dev/null 2>&1 || true
            fi
        done < <(ufw status numbered 2>/dev/null | awk -v c="$comment" 'index($0,c){n=$1;gsub(/[^0-9]/,"",n);print n}' | sort -rn)
    }
    trap firewall_rollback ERR INT TERM
    for port in 80 443; do
        while IFS= read -r cidr; do
            [[ -n "$cidr" ]] || continue
            if ! rule_exists "$cidr" "$port" "$comment"; then
                run ufw allow from "$cidr" to any port "$port" proto tcp comment "$comment"
                added+=("$cidr:$port")
            fi
        done < <(cat "$ranges/ipv4" "$ranges/ipv6")
    done
    local expected=$((($(wc -l <"$ranges/ipv4") + $(wc -l <"$ranges/ipv6")) * 2))
    local actual
    actual="$(ufw status 2>/dev/null | grep -Fc "$comment" || true)"
    if [[ "$DRY_RUN" != true && "$actual" -lt "$expected" ]]; then
        die "UFW verification failed: expected at least $expected managed rules, found $actual"
    fi
    trap - ERR INT TERM
    while IFS= read -r number; do [[ -n "$number" ]] && run ufw --force delete "$number"; done < <(managed_rule_numbers "$digest")
    if [[ "$DRY_RUN" != true ]]; then
        printf '%s\n' "$digest" >"$STATE_DIR/firewall-digest"
    fi
    info "Cloudflare-only UFW rules are current ($digest); SSH and unrelated rules were untouched"
}

remove_managed_firewall() {
    local number
    require_command ufw
    while IFS= read -r number; do [[ -n "$number" ]] && run ufw --force delete "$number"; done < <(managed_rule_numbers)
}
