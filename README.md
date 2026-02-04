# 🔐 Cloudflare Edge Guard

Production-ready origin hardening toolkit for servers behind Cloudflare.

This script automatically:

- Restricts UFW to allow only Cloudflare IP ranges (80/443)
- Configures Nginx `real_ip` settings
- Validates and safely reloads Nginx
- Prevents accidental lockouts with fail-safe logic
- Designed for automated daily execution via cron

---

## 🎯 Why?

When running a server behind Cloudflare, your origin IP should never be directly exposed.

This tool ensures:

- Only Cloudflare edge IPs can reach ports 80 and 443
- Real visitor IPs are correctly passed to Nginx
- Cloudflare IP changes are handled automatically
- No downtime during updates

---

## ⚙️ Requirements

- Ubuntu / Debian
- UFW enabled
- Nginx installed
- Root privileges

---

## 🚀 Installation

Copy script:

```bash
sudo cp cf-edge-guard.sh /usr/local/bin/
sudo chmod +x /usr/local

Add to root crontab:
sudo crontab -e
0 4 * * * flock -n /tmp/cf_edge.lock /usr/local/bin/cf-edge-guard.sh >> /var/log/cf_edge_update.log 2>&1
```

🛡️ Security Design

Fail-safe: aborts if Cloudflare IP list fetch fails

Idempotent: does not duplicate rules

Safe reload: validates nginx -t before applying changes

Logs all operations

📦 What It Does

Fetches Cloudflare IPv4 + IPv6 ranges

Removes existing 80/443 UFW rules (non-SSH)

Inserts Cloudflare-only allow rules

Updates Nginx real IP configuration

Reloads Nginx safely

🧠 Use Case

Ideal for:

SaaS backends

API servers

Production VPS behind Cloudflare

Self-hosted platform

⚠️ Important

Ensure:

```
sudo ufw status verbose
```

Shows:

```
Default: deny (incoming)
```
