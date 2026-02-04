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
