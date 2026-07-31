#!/usr/bin/env bash

set -Eeuo pipefail

declare -A EDGE_CONFIG=()

config_defaults() {
    EDGE_CONFIG=(
        [ENABLE_WWW]=true [UPSTREAM_HOST]=127.0.0.1 [UPSTREAM_PORT]=8080
        [HEALTHCHECK_PATH]=/health [ENABLE_NGINX]=true [ENABLE_HTTP_REDIRECT]=true
        [ENABLE_ORIGIN_TLS]=true [ENABLE_UFW]=true [SSH_PORT]=22
        [ENABLE_CLOUDFLARE_EDGE_GUARD]=true [ENABLE_IPV6]=true
        [CLOUDFLARE_IPV4_URL]=https://www.cloudflare.com/ips-v4
        [CLOUDFLARE_IPV6_URL]=https://www.cloudflare.com/ips-v6
        [ENABLE_AUTOMATIC_UPDATES]=true [UPDATE_SCHEDULE]=04:00
        [LOG_FILE]=/var/log/cloudflare-edge-guard.log
        [STATE_DIR]=/var/lib/cloudflare-edge-guard
        [BACKUP_DIR]=/var/backups/cloudflare-edge-guard
        [NGINX_SITE_PATH]=/etc/nginx/sites-available/cloudflare-edge-guard.conf
        [NGINX_SITE_LINK]=/etc/nginx/sites-enabled/cloudflare-edge-guard.conf
        [NGINX_REALIP_PATH]=/etc/nginx/conf.d/00-cloudflare-edge-guard-realip.conf
        [DRY_RUN]=false
    )
}

load_config() {
    local file="$1" raw key value command_sub='$' line=0
    [[ -r "$file" ]] || die "Configuration is not readable: $file"
    config_defaults
    while IFS= read -r raw || [[ -n "$raw" ]]; do
        ((line += 1))
        raw="${raw%$'\r'}"
        [[ "$raw" =~ ^[[:space:]]*$ || "$raw" =~ ^[[:space:]]*# ]] && continue
        [[ "$raw" =~ ^([A-Z][A-Z0-9_]*)=(.*)$ ]] || die "Invalid config syntax at $file:$line"
        key="${BASH_REMATCH[1]}"
        value="${BASH_REMATCH[2]}"
        if [[ ! -v "EDGE_CONFIG[$key]" && "$key" != DOMAIN && "$key" != ORIGIN_CERT_PATH && "$key" != ORIGIN_KEY_PATH ]]; then
            die "Unknown configuration key at $file:$line: $key"
        fi
        [[ "$value" != *"$command_sub("* && "$value" != *'`'* && "$value" != *$'\n'* ]] || die "Unsafe value for $key"
        [[ "$value" != *'"'* && "$value" != *"'"* && "$value" != *';'* ]] || die "Quotes and shell separators are not supported for $key"
        EDGE_CONFIG["$key"]="$value"
    done <"$file"
    apply_config
    validate_config
}

apply_config() {
    local key
    for key in "${!EDGE_CONFIG[@]}"; do
        printf -v "$key" '%s' "${EDGE_CONFIG[$key]}"
    done
}

valid_bool() { [[ "$1" == true || "$1" == false ]]; }
valid_port() { [[ "$1" =~ ^[0-9]+$ ]] && ((10#$1 >= 1 && 10#$1 <= 65535)); }

validate_config() {
    local key healthcheck_pattern
    [[ -n "${DOMAIN:-}" ]] || die "DOMAIN is required"
    [[ "$DOMAIN" =~ ^([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,63}$ ]] || die "Invalid DOMAIN: $DOMAIN"
    [[ "$UPSTREAM_HOST" == 127.0.0.1 || "$UPSTREAM_HOST" == localhost || "$UPSTREAM_HOST" == ::1 ]] || die "UPSTREAM_HOST must be loopback"
    valid_port "$UPSTREAM_PORT" || die "Invalid UPSTREAM_PORT"
    valid_port "$SSH_PORT" || die "Invalid SSH_PORT"
    healthcheck_pattern='^/[A-Za-z0-9._~!$&()*+,;=:@%/-]*$'
    [[ "$HEALTHCHECK_PATH" =~ $healthcheck_pattern && "$HEALTHCHECK_PATH" != *'..'* ]] || die "Invalid HEALTHCHECK_PATH"
    for key in ENABLE_WWW ENABLE_NGINX ENABLE_HTTP_REDIRECT ENABLE_ORIGIN_TLS ENABLE_UFW ENABLE_CLOUDFLARE_EDGE_GUARD ENABLE_IPV6 ENABLE_AUTOMATIC_UPDATES DRY_RUN; do
        valid_bool "${!key}" || die "Invalid boolean $key=${!key}"
    done
    [[ "$CLOUDFLARE_IPV4_URL" == https://www.cloudflare.com/ips-v4 ]] || die "CLOUDFLARE_IPV4_URL must use the official Cloudflare endpoint"
    [[ "$CLOUDFLARE_IPV6_URL" == https://www.cloudflare.com/ips-v6 ]] || die "CLOUDFLARE_IPV6_URL must use the official Cloudflare endpoint"
    [[ "$UPDATE_SCHEDULE" =~ ^([01][0-9]|2[0-3]):[0-5][0-9]$ ]] || die "Invalid UPDATE_SCHEDULE"
    if [[ "$ENABLE_ORIGIN_TLS" == true ]]; then
        [[ -n "${ORIGIN_CERT_PATH:-}" && -n "${ORIGIN_KEY_PATH:-}" ]] || die "Origin TLS requires ORIGIN_CERT_PATH and ORIGIN_KEY_PATH"
        if [[ "$DRY_RUN" != true ]]; then
            [[ -r "$ORIGIN_CERT_PATH" ]] || die "Origin certificate is not readable: $ORIGIN_CERT_PATH"
            [[ -r "$ORIGIN_KEY_PATH" ]] || die "Origin private key is not readable: $ORIGIN_KEY_PATH"
            local key_mode
            key_mode="$(stat -c '%a' "$ORIGIN_KEY_PATH")"
            ((10#$key_mode <= 640)) || die "Origin private key permissions are too broad ($key_mode); use 600 or 640"
        fi
    fi
}
