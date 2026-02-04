#!/bin/bash
set -euo pipefail

# Logs
LOG="/var/log/cf_edge_update.log"
log(){ echo "[$(date -u)] $*" >> "$LOG"; }

# Endpoints
CF_V4_URL="https://www.cloudflare.com/ips-v4"
CF_V6_URL="https://www.cloudflare.com/ips-v6"

# Nginx realip output file (must be included by nginx)
NGX_REALIP="/etc/nginx/conf.d/00-cloudflare_realip.conf"

TMP_V4="$(mktemp)"
TMP_V6="$(mktemp)"
TMP_ALL="$(mktemp)"
TMP_NGX="$(mktemp)"

cleanup(){ rm -f "$TMP_V4" "$TMP_V6" "$TMP_ALL" "$TMP_NGX"; }
trap cleanup EXIT

log "==== Cloudflare EDGE update start ===="

# 1) Fetch IP ranges once
curl -fsSL "$CF_V4_URL" | tr -d '\r' | sed '/^\s*$/d' > "$TMP_V4"
curl -fsSL "$CF_V6_URL" | tr -d '\r' | sed '/^\s*$/d' > "$TMP_V6"

# Fail-safe
if [[ ! -s "$TMP_V4" || ! -s "$TMP_V6" ]]; then
  log "ERROR: Cloudflare IP fetch failed or empty. No changes applied."
  log ""
  exit 1
fi

# Unified list (unique) for diff/logging if needed
{ cat "$TMP_V4"; echo; cat "$TMP_V6"; } | sed '/^\s*$/d' | sort -u > "$TMP_ALL"
V4_COUNT="$(wc -l < "$TMP_V4" | tr -d ' ')"
V6_COUNT="$(wc -l < "$TMP_V6" | tr -d ' ')"
log "Fetched ranges: v4=$V4_COUNT, v6=$V6_COUNT"

########################################
# 2) Update UFW (80/443 allow only CF)
########################################

# Delete ALL existing 80/443 rules (ALLOW/DENY) except OpenSSH
DELETED=0
while :; do
  NUM="$(ufw status numbered | awk '/\[[0-9]+\].*(80\/tcp|443\/tcp).*(ALLOW IN|DENY IN)/ && $0 !~ /OpenSSH/ {print $1}' \
    | head -n1 | tr -d '[]' || true)"
  [[ -z "$NUM" ]] && break
  ufw --force delete "$NUM" >> "$LOG"
  DELETED=$((DELETED+1))
done
log "UFW: deleted existing 80/443 rules (non-SSH): $DELETED"

# Add rules at top (prepend if available, else insert 1, else allow)
add_top_ufw() {
  if ufw --help 2>/dev/null | grep -q '^ *prepend '; then
    ufw prepend allow "$@" >> "$LOG"
  else
    if ufw status numbered | grep -q '^\['; then
      ufw insert 1 allow "$@" >> "$LOG" || ufw allow "$@" >> "$LOG"
    else
      ufw allow "$@" >> "$LOG"
    fi
  fi
}

ADDED_RULES=0

# 80
while read -r ip; do [[ -n "$ip" ]] && add_top_ufw from "$ip" to any port 80 proto tcp && ADDED_RULES=$((ADDED_RULES+1)); done < "$TMP_V4"
while read -r ip; do [[ -n "$ip" ]] && add_top_ufw from "$ip" to any port 80 proto tcp && ADDED_RULES=$((ADDED_RULES+1)); done < "$TMP_V6"
# 443
while read -r ip; do [[ -n "$ip" ]] && add_top_ufw from "$ip" to any port 443 proto tcp && ADDED_RULES=$((ADDED_RULES+1)); done < "$TMP_V4"
while read -r ip; do [[ -n "$ip" ]] && add_top_ufw from "$ip" to any port 443 proto tcp && ADDED_RULES=$((ADDED_RULES+1)); done < "$TMP_V6"

log "UFW: added CF rules total: $ADDED_RULES"
log "UFW: default policy should be deny incoming (check: ufw status verbose)"

########################################
# 3) Update Nginx realip config
########################################

{
  echo "# Auto-generated Cloudflare real IP config. Do not edit."
  echo "real_ip_header CF-Connecting-IP;"
  echo "real_ip_recursive on;"
  echo ""
  echo "# IPv4"
  while read -r ip; do [[ -n "$ip" ]] && echo "set_real_ip_from $ip;"; done < "$TMP_V4"
  echo ""
  echo "# IPv6"
  while read -r ip; do [[ -n "$ip" ]] && echo "set_real_ip_from $ip;"; done < "$TMP_V6"
  echo ""
} > "$TMP_NGX"

if [[ -f "$NGX_REALIP" ]] && cmp -s "$TMP_NGX" "$NGX_REALIP"; then
  log "Nginx: realip file unchanged (no reload)."
else
  sudo mv "$TMP_NGX" "$NGX_REALIP"
  log "Nginx: updated $NGX_REALIP"

  if sudo nginx -t >> "$LOG" 2>&1; then
    sudo systemctl reload nginx >> "$LOG" 2>&1 || sudo nginx -s reload >> "$LOG" 2>&1
    log "Nginx: reload OK"
  else
    log "ERROR: nginx -t failed; NOT reloading."
    log ""
    exit 1
  fi
fi

log "==== Cloudflare EDGE update done ===="
log ""
