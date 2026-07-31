#!/usr/bin/env bats

load test_helper

setup() {
    setup_workspace
    write_config
}
teardown() { teardown_workspace; }

@test "valid configuration loads without executing values" {
    run bash -c 'source lib/common.sh; source lib/config.sh; load_config "$1"; printf "%s:%s" "$DOMAIN" "$UPSTREAM_PORT"' _ "$TEST_ROOT/config.env"
    [ "$status" -eq 0 ]
    [ "$output" = "example.com:8080" ]
}

@test "missing domain is rejected" {
    sed -i '/^DOMAIN=/d' "$TEST_ROOT/config.env"
    run bash -c 'source lib/common.sh; source lib/config.sh; load_config "$1"' _ "$TEST_ROOT/config.env"
    [ "$status" -ne 0 ]
    [[ "$output" == *"DOMAIN is required"* ]]
}

@test "invalid boolean is rejected" {
    sed -i 's/ENABLE_UFW=false/ENABLE_UFW=yes/' "$TEST_ROOT/config.env"
    run bash -c 'source lib/common.sh; source lib/config.sh; load_config "$1"' _ "$TEST_ROOT/config.env"
    [ "$status" -ne 0 ]
}

@test "invalid domain and port are rejected" {
    sed -i 's/example.com/bad_domain/' "$TEST_ROOT/config.env"
    run bash -c 'source lib/common.sh; source lib/config.sh; load_config "$1"' _ "$TEST_ROOT/config.env"
    [ "$status" -ne 0 ]
    sed -i 's/bad_domain/example.com/; s/UPSTREAM_PORT=8080/UPSTREAM_PORT=70000/' "$TEST_ROOT/config.env"
    run bash -c 'source lib/common.sh; source lib/config.sh; load_config "$1"' _ "$TEST_ROOT/config.env"
    [ "$status" -ne 0 ]
}

@test "shell substitution and quoted secret values are rejected" {
    printf 'EVIL=$(touch %s/pwned)\n' "$TEST_ROOT" >>"$TEST_ROOT/config.env"
    run bash -c 'source lib/common.sh; source lib/config.sh; load_config "$1"' _ "$TEST_ROOT/config.env"
    [ "$status" -ne 0 ]
    [ ! -e "$TEST_ROOT/pwned" ]
}
