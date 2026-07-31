#!/usr/bin/env bash

set -Eeuo pipefail

validate_ranges() {
    local file="$1" family="$2" line count=0
    [[ -s "$file" ]] || die "Cloudflare IPv$family response is empty"
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -n "$line" ]] || continue
        if [[ "$family" == 4 ]]; then
            [[ "$line" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/([0-9]|[12][0-9]|3[0-2])$ ]] || die "Malformed IPv4 CIDR: $line"
            local address octet
            address="${line%/*}"
            IFS=. read -r -a octet <<<"$address"
            ((10#${octet[0]} <= 255 && 10#${octet[1]} <= 255 && 10#${octet[2]} <= 255 && 10#${octet[3]} <= 255)) || die "Malformed IPv4 CIDR: $line"
        else
            [[ "$line" =~ ^[0-9A-Fa-f:]+/([0-9]|[1-9][0-9]|1[01][0-9]|12[0-8])$ && "$line" == *:* ]] || die "Malformed IPv6 CIDR: $line"
        fi
        ((count += 1))
    done <"$file"
    local minimum=5
    [[ "$family" == 4 ]] && minimum=10
    ((count >= minimum)) || die "Suspiciously incomplete Cloudflare IPv$family response ($count ranges)"
}

fetch_ranges() {
    local output_dir="$1"
    require_command curl
    ensure_dir "$output_dir" 0700
    local v4="$output_dir/ipv4" v6="$output_dir/ipv6"
    curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 --connect-timeout 10 --max-time 30 "$CLOUDFLARE_IPV4_URL" |
        tr -d '\r' | awk 'NF && !seen[$0]++' | LC_ALL=C sort >"$v4" || die "Failed to fetch Cloudflare IPv4 ranges"
    validate_ranges "$v4" 4
    if [[ "$ENABLE_IPV6" == true ]]; then
        curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 --connect-timeout 10 --max-time 30 "$CLOUDFLARE_IPV6_URL" |
            tr -d '\r' | awk 'NF && !seen[$0]++' | LC_ALL=C sort >"$v6" || die "Failed to fetch Cloudflare IPv6 ranges"
        validate_ranges "$v6" 6
    else
        : >"$v6"
    fi
}

ranges_digest() { cat "$1/ipv4" "$1/ipv6" | sha256sum | awk '{print substr($1,1,12)}'; }
