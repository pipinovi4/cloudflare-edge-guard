#!/usr/bin/env bats

load test_helper
setup() {
    setup_workspace
    write_config
}
teardown() { teardown_workspace; }

@test "prepare implementation never calls firewall application" {
    run awk '/^do_prepare\(\)/,/^\)/' edge-guard.sh
    [ "$status" -eq 0 ]
    [[ "$output" != *"apply_firewall"* ]]
}

@test "enforce orders preflight checks before update" {
    run awk '/^do_enforce\(\)/,/^}/' edge-guard.sh
    [ "$status" -eq 0 ]
    check_line="$(printf '%s\n' "$output" | grep -n 'check_upstream' | cut -d: -f1)"
    update_line="$(printf '%s\n' "$output" | grep -n 'do_update' | cut -d: -f1)"
    [ "$check_line" -lt "$update_line" ]
}

@test "legacy update command delegates to the safe CLI" {
    run grep -F 'edge-guard.sh" update' scripts/update_cf_edge.sh
    [ "$status" -eq 0 ]
}
