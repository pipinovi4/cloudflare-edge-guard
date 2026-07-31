#!/usr/bin/env bats

load test_helper
setup() { setup_workspace; }
teardown() { teardown_workspace; }

@test "official-sized IPv4 and IPv6 fixtures validate" {
    run bash -c 'source lib/common.sh; source lib/cloudflare.sh; validate_ranges tests/fixtures/ips-v4 4; validate_ranges tests/fixtures/ips-v6 6'
    [ "$status" -eq 0 ]
}

@test "empty HTML malformed and partial responses fail closed" {
    : >"$TEST_ROOT/empty"
    printf '<html>error</html>\n' >"$TEST_ROOT/html"
    printf '173.245.48.0/20\n' >"$TEST_ROOT/partial"
    for fixture in empty html partial; do
        run bash -c 'source lib/common.sh; source lib/cloudflare.sh; validate_ranges "$1" 4' _ "$TEST_ROOT/$fixture"
        [ "$status" -ne 0 ]
    done
}

@test "duplicate ranges produce a stable digest after fetch normalization" {
    mkdir -p "$TEST_ROOT/a" "$TEST_ROOT/b"
    cp tests/fixtures/ips-v4 "$TEST_ROOT/a/ipv4"
    cp tests/fixtures/ips-v6 "$TEST_ROOT/a/ipv6"
    sort -u tests/fixtures/ips-v4 >"$TEST_ROOT/b/ipv4"
    sort -u tests/fixtures/ips-v6 >"$TEST_ROOT/b/ipv6"
    run bash -c 'source lib/cloudflare.sh; ranges_digest "$1"' _ "$TEST_ROOT/b"
    [ "$status" -eq 0 ]
}
