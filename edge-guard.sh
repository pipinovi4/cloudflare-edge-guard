#!/usr/bin/env bash
set -Eeuo pipefail

EDGE_GUARD_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$EDGE_GUARD_ROOT/lib/common.sh"
# shellcheck source=lib/config.sh
source "$EDGE_GUARD_ROOT/lib/config.sh"
# shellcheck source=lib/cloudflare.sh
source "$EDGE_GUARD_ROOT/lib/cloudflare.sh"
# shellcheck source=lib/nginx.sh
source "$EDGE_GUARD_ROOT/lib/nginx.sh"
# shellcheck source=lib/firewall.sh
source "$EDGE_GUARD_ROOT/lib/firewall.sh"
# shellcheck source=lib/preflight.sh
source "$EDGE_GUARD_ROOT/lib/preflight.sh"

usage() {
    cat <<'EOF'
Usage: edge-guard.sh COMMAND [--config PATH] [--dry-run] [--verbose]

Commands:
  prepare    Configure and validate Nginx; never restrict the firewall
  enforce    Run preflights and enforce Cloudflare-only web access
  update     Update Cloudflare ranges and managed configuration
  verify     Verify upstream, DNS, Nginx, and managed firewall state
  status     Show configuration and managed state without changing it
  uninstall  Remove only files and UFW rules managed by this toolkit

Options: --config PATH  --dry-run  --verbose  --help  --version
EOF
}

version() {
    tr -d '\r\n' <"$EDGE_GUARD_ROOT/VERSION"
    printf '\n'
}

COMMAND="${1:-}"
if [[ $# -gt 0 ]]; then
    shift
fi
CONFIG_FILE="/etc/cloudflare-edge-guard/config.env"
CLI_DRY_RUN=false
while (($#)); do
    case "$1" in
        --config)
            [[ $# -ge 2 ]] || die "--config requires a path"
            CONFIG_FILE="$2"
            shift 2
            ;;
        --dry-run)
            CLI_DRY_RUN=true
            shift
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        --help | -h)
            usage
            exit 0
            ;;
        --version | -V)
            version
            exit 0
            ;;
        *) die "Unknown option: $1" ;;
    esac
done
case "$COMMAND" in --help | -h)
    usage
    exit 0
    ;;
--version | -V)
    version
    exit 0
    ;;
'')
    usage
    exit 2
    ;;
esac
load_config "$CONFIG_FILE"
[[ "$CLI_DRY_RUN" == true ]] && DRY_RUN=true
[[ "$DRY_RUN" == true ]] && EDGE_GUARD_ALLOW_NON_ROOT=true
ensure_dir "$STATE_DIR"
ensure_dir "$BACKUP_DIR"

prepare_ranges() {
    local destination="$1"
    if [[ -s "$STATE_DIR/ranges/ipv4" ]]; then
        ensure_dir "$destination" 0700
        cp "$STATE_DIR/ranges/ipv4" "$destination/ipv4"
        cp "$STATE_DIR/ranges/ipv6" "$destination/ipv6"
    else
        fetch_ranges "$destination"
    fi
}

do_prepare() (
    preflight_base
    check_upstream
    local temporary
    temporary="$(mktemp -d)"
    trap 'rm -rf -- "$temporary"' EXIT
    prepare_ranges "$temporary"
    apply_nginx "$temporary"
    info "Prepare complete; firewall was not restricted"
)

do_update() (
    preflight_base
    local temporary
    temporary="$(mktemp -d)"
    trap 'rm -rf -- "$temporary"' EXIT
    fetch_ranges "$temporary"
    if [[ -d "$STATE_DIR/ranges" ]] && cmp -s "$temporary/ipv4" "$STATE_DIR/ranges/ipv4" && cmp -s "$temporary/ipv6" "$STATE_DIR/ranges/ipv6"; then
        apply_nginx "$temporary"
        apply_firewall "$temporary"
        info "Cloudflare ranges unchanged"
        return 0
    fi
    apply_nginx "$temporary"
    apply_firewall "$temporary"
    ensure_dir "$STATE_DIR/ranges" 0700
    run install -m 0644 "$temporary/ipv4" "$STATE_DIR/ranges/ipv4"
    run install -m 0644 "$temporary/ipv6" "$STATE_DIR/ranges/ipv6"
    info "Cloudflare ranges updated"
)

do_enforce() {
    preflight_base
    check_domain
    check_upstream
    nginx_test
    do_update
    info "Enforcement complete"
}

do_verify() {
    preflight_base
    check_domain
    check_upstream
    [[ "$ENABLE_NGINX" == true ]] && nginx_test
    if [[ "$ENABLE_UFW" == true ]]; then
        ufw_active || die "UFW is not active"
        ufw status | grep -q 'cloudflare-edge-guard:' || die "No managed firewall rules found"
    fi
    info "Verification passed"
}

do_status() {
    printf 'Domain: %s\nUpstream: %s:%s\nDry run: %s\n' "$DOMAIN" "$UPSTREAM_HOST" "$UPSTREAM_PORT" "$DRY_RUN"
    [[ -f "$STATE_DIR/firewall-digest" ]] && printf 'Firewall digest: %s\n' "$(cat "$STATE_DIR/firewall-digest")" || printf 'Firewall: not enforced\n'
}

do_uninstall() {
    preflight_base
    [[ "$ENABLE_UFW" == true ]] && remove_managed_firewall
    backup_file "$NGINX_SITE_PATH"
    backup_file "$NGINX_REALIP_PATH"
    run rm -f -- "$NGINX_SITE_LINK" "$NGINX_SITE_PATH" "$NGINX_REALIP_PATH"
    [[ "$ENABLE_NGINX" == true ]] && nginx_test && nginx_reload
    info "Managed configuration removed; certificates, SSH, and unrelated rules were untouched"
}

case "$COMMAND" in
    prepare) with_lock "$STATE_DIR/edge-guard.lock" do_prepare ;;
    enforce) with_lock "$STATE_DIR/edge-guard.lock" do_enforce ;;
    update) with_lock "$STATE_DIR/edge-guard.lock" do_update ;;
    verify) do_verify ;;
    status) do_status ;;
    uninstall) with_lock "$STATE_DIR/edge-guard.lock" do_uninstall ;;
    *)
        usage >&2
        die "Unknown command: $COMMAND"
        ;;
esac
