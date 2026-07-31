#!/usr/bin/env bats

load test_helper
setup() {
    setup_workspace
    write_config
    source lib/common.sh
    source lib/config.sh
    source lib/nginx.sh
    load_config "$TEST_ROOT/config.env"
}
teardown() { teardown_workspace; }

@test "site rendering includes domain www and loopback upstream without TLS" {
    render_site "$TEST_ROOT/site"
    grep -q 'server_name example.com www.example.com' "$TEST_ROOT/site"
    grep -q 'proxy_pass http://127.0.0.1:8080' "$TEST_ROOT/site"
    ! grep -q 'listen 443' "$TEST_ROOT/site"
}

@test "real IP rendering includes both address families" {
    mkdir "$TEST_ROOT/ranges"
    cp tests/fixtures/ips-v4 "$TEST_ROOT/ranges/ipv4"
    cp tests/fixtures/ips-v6 "$TEST_ROOT/ranges/ipv6"
    render_realip "$TEST_ROOT/ranges" "$TEST_ROOT/realip"
    grep -q 'set_real_ip_from 173.245.48.0/20;' "$TEST_ROOT/realip"
    grep -q 'set_real_ip_from 2400:cb00::/32;' "$TEST_ROOT/realip"
}
