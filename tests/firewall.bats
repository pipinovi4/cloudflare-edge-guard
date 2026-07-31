#!/usr/bin/env bats

load test_helper
setup() {
    setup_workspace
    mkdir "$TEST_ROOT/ranges"
    cp tests/fixtures/ips-v4 "$TEST_ROOT/ranges/ipv4"
    : >"$TEST_ROOT/ranges/ipv6"
    cat >"$TEST_ROOT/bin/ufw" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$TEST_ROOT/ufw.calls"
case "$*" in
    status) printf 'Status: active\n22/tcp ALLOW IN Anywhere # ssh\n' ;;
    'status numbered') printf 'Status: active\n[ 1] 22/tcp ALLOW IN Anywhere # ssh\n[ 2] 80/tcp ALLOW IN 192.0.2.0/24 # unrelated\n' ;;
esac
EOF
    chmod +x "$TEST_ROOT/bin/ufw"
    export ENABLE_UFW=true ENABLE_CLOUDFLARE_EDGE_GUARD=true DRY_RUN=true STATE_DIR="$TEST_ROOT/state"
}
teardown() { teardown_workspace; }

@test "dry run generates Cloudflare rules without deleting SSH or unrelated rules" {
    run bash -c 'source lib/common.sh; source lib/cloudflare.sh; source lib/firewall.sh; apply_firewall "$1"' _ "$TEST_ROOT/ranges"
    [ "$status" -eq 0 ]
    [[ "$output" == *"ufw allow from 173.245.48.0/20"* ]]
    ! grep -q -- '--force delete' "$TEST_ROOT/ufw.calls"
    grep -q '^status' "$TEST_ROOT/ufw.calls"
}

@test "managed rule selector ignores SSH and untagged web rules" {
    run bash -c 'source lib/common.sh; source lib/cloudflare.sh; source lib/firewall.sh; managed_rule_numbers'
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}
