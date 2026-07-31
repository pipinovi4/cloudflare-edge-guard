setup_workspace() {
    TEST_ROOT="$(mktemp -d)"
    export TEST_ROOT EDGE_GUARD_ALLOW_NON_ROOT=true
    mkdir -p "$TEST_ROOT/bin" "$TEST_ROOT/state" "$TEST_ROOT/backups" "$TEST_ROOT/nginx/available" "$TEST_ROOT/nginx/enabled" "$TEST_ROOT/nginx/conf.d"
    export PATH="$TEST_ROOT/bin:$PATH"
}

teardown_workspace() { rm -rf -- "$TEST_ROOT"; }

write_config() {
    cat >"$TEST_ROOT/config.env" <<EOF
DOMAIN=example.com
ENABLE_WWW=true
UPSTREAM_HOST=127.0.0.1
UPSTREAM_PORT=8080
HEALTHCHECK_PATH=/health
ENABLE_NGINX=false
ENABLE_HTTP_REDIRECT=true
ENABLE_ORIGIN_TLS=false
ENABLE_UFW=false
SSH_PORT=22
ENABLE_CLOUDFLARE_EDGE_GUARD=true
ENABLE_IPV6=true
CLOUDFLARE_IPV4_URL=https://www.cloudflare.com/ips-v4
CLOUDFLARE_IPV6_URL=https://www.cloudflare.com/ips-v6
ENABLE_AUTOMATIC_UPDATES=false
UPDATE_SCHEDULE=04:00
LOG_FILE=$TEST_ROOT/edge.log
STATE_DIR=$TEST_ROOT/state
BACKUP_DIR=$TEST_ROOT/backups
NGINX_SITE_PATH=$TEST_ROOT/nginx/available/site.conf
NGINX_SITE_LINK=$TEST_ROOT/nginx/enabled/site.conf
NGINX_REALIP_PATH=$TEST_ROOT/nginx/conf.d/realip.conf
DRY_RUN=false
EOF
}
