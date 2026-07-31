#!/usr/bin/env bash

set -Eeuo pipefail

render_realip() {
    local ranges="$1" output="$2" ip
    {
        printf '# Managed by cloudflare-edge-guard. Do not edit.\nreal_ip_header CF-Connecting-IP;\nreal_ip_recursive on;\n'
        while IFS= read -r ip; do [[ -n "$ip" ]] && printf 'set_real_ip_from %s;\n' "$ip"; done <"$ranges/ipv4"
        while IFS= read -r ip; do [[ -n "$ip" ]] && printf 'set_real_ip_from %s;\n' "$ip"; done <"$ranges/ipv6"
    } >"$output"
}

render_site() {
    local output="$1" names="$DOMAIN"
    [[ "$ENABLE_WWW" == true ]] && names="$names www.$DOMAIN"
    {
        printf '# Managed by cloudflare-edge-guard. Do not edit.\n'
        if [[ "$ENABLE_HTTP_REDIRECT" == true && "$ENABLE_ORIGIN_TLS" == true ]]; then
            printf "server {\n    listen 80;\n    listen [::]:80;\n    server_name %s;\n    return 301 https://\$host\$request_uri;\n}\n" "$names"
        else
            printf 'server {\n    listen 80;\n    listen [::]:80;\n    server_name %s;\n' "$names"
            render_proxy_block
            printf '}\n'
        fi
        if [[ "$ENABLE_ORIGIN_TLS" == true ]]; then
            printf 'server {\n    listen 443 ssl;\n    listen [::]:443 ssl;\n    server_name %s;\n    ssl_certificate %s;\n    ssl_certificate_key %s;\n    ssl_protocols TLSv1.2 TLSv1.3;\n' "$names" "$ORIGIN_CERT_PATH" "$ORIGIN_KEY_PATH"
            render_proxy_block
            printf '}\n'
        fi
    } >"$output"
}

render_proxy_block() {
    cat <<EOF
    server_tokens off;
    add_header X-Content-Type-Options nosniff always;
    add_header X-Frame-Options DENY always;
    add_header Referrer-Policy strict-origin-when-cross-origin always;
    location / {
        proxy_pass http://${UPSTREAM_HOST}:${UPSTREAM_PORT};
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 60s;
        proxy_send_timeout 60s;
    }
EOF
}

nginx_test() { run nginx -t; }
nginx_reload() { run systemctl reload nginx; }

apply_nginx() (
    local ranges="$1" temporary changed=false site_tmp realip_tmp
    [[ "$ENABLE_NGINX" == true ]] || return 0
    require_command nginx
    temporary="$(mktemp -d)"
    site_tmp="$temporary/site" realip_tmp="$temporary/realip"
    trap 'rm -rf -- "$temporary"' EXIT
    render_site "$site_tmp"
    render_realip "$ranges" "$realip_tmp"
    ensure_dir "$(dirname "$NGINX_SITE_PATH")"
    ensure_dir "$(dirname "$NGINX_REALIP_PATH")"
    if install_if_changed "$site_tmp" "$NGINX_SITE_PATH"; then
        changed=true
    fi
    if install_if_changed "$realip_tmp" "$NGINX_REALIP_PATH"; then
        changed=true
    fi
    if [[ ! -L "$NGINX_SITE_LINK" || "$(readlink "$NGINX_SITE_LINK" 2>/dev/null || true)" != "$NGINX_SITE_PATH" ]]; then
        backup_file "$NGINX_SITE_LINK"
        run ln -sfn "$NGINX_SITE_PATH" "$NGINX_SITE_LINK"
        changed=true
    fi
    if [[ "$changed" == true ]]; then
        nginx_test || die "nginx -t failed; configuration was not reloaded (restore from $BACKUP_DIR)"
        nginx_reload
    else
        nginx_test
    fi
)
