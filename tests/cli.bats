#!/usr/bin/env bats

load test_helper
setup() {
    setup_workspace
    write_config
}
teardown() { teardown_workspace; }

@test "help and version work without configuration" {
    run bash ./edge-guard.sh --help
    [ "$status" -eq 0 ]
    run bash ./edge-guard.sh --version
    [ "$status" -eq 0 ]
    [ "$output" = "2.0.0" ]
}

@test "unknown command and missing config return nonzero" {
    run bash ./edge-guard.sh nonsense --config "$TEST_ROOT/config.env"
    [ "$status" -ne 0 ]
    run bash ./edge-guard.sh status --config "$TEST_ROOT/missing"
    [ "$status" -ne 0 ]
}

@test "status is read only" {
    run bash ./edge-guard.sh status --config "$TEST_ROOT/config.env"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Domain: example.com"* ]]
}
