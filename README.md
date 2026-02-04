# 🔐 Cloudflare Edge Guard

Production-ready origin hardening toolkit for servers running behind Cloudflare.

This repository contains a secure, idempotent automation script that restricts direct access to your origin server and ensures only Cloudflare edge IP ranges can reach ports 80 and 443.

---

## 🚀 What This Solves

When using Cloudflare, your origin server should **never be publicly accessible**.

Without proper firewall isolation:
- Attackers can bypass Cloudflare by hitting the origin IP directly
- Rate limits and WAF rules can be avoided
- Real client IP logging may not work correctly

Cloudflare Edge Guard enforces proper origin isolation automatically.

---

## 🛡️ Features

- 🔒 Restricts UFW to allow **only Cloudflare IP ranges**
- 🌍 Supports IPv4 and IPv6
- 🧠 Automatically configures Nginx `real_ip`
- 🔄 Safely reloads Nginx (`nginx -t` validation)
- 🚫 Fail-safe: aborts if Cloudflare IP fetch fails
- 🔁 Designed for automated daily execution (cron)
- 🧾 Logs all operations

---

## 📦 Repository Structure
```bash
cloudflare-edge-guard/
│
├── scripts/
│ └── update_cf_edge.sh
│
├── nginx/
│ ├── nginx.conf
│ ├── cloudflare_realip.conf
│ ├── sites-available/
│ └── sites-enabled/
│
├── cron/
│ └── root_cron_example
│
├── VERSION
├── .gitignore
└── README.md
```

---

## ⚙️ Requirements

- Ubuntu / Debian
- UFW enabled
- Nginx installed
- Root privileges
- Server operating behind Cloudflare proxy (orange cloud)

---

## 🔧 Installation

### 1️⃣ Copy the script

```bash
sudo cp scripts/update_cf_edge.sh /usr/local/bin/cf-edge-guard.sh
sudo chmod +x /usr/local/bin/cf-edge-guard.sh
```

### 2️⃣ Run manually (optional test)

```bash
sudo /usr/local/bin/cf-edge-guard.sh
```

### 3️⃣ Add automated daily execution

Edit root crontab:

```bash
sudo crontab -e
```

Add:

```bash
0 4 * * * flock -n /tmp/cf_edge.lock /usr/local/bin/cf-edge-guard.sh >> /var/log/cf_edge_update.log 2>&1
```

### This will:
* Run daily at 04:00 UTC
* Prevent overlapping executions
* Log output safely

### 🔍 What The Script Does
1. Fetches official Cloudflare IPv4 and IPv6 ranges
2. Verifies ranges are not empty (fail-safe protection)
3. Removes existing 80/443 UFW rules (non-SSH)
4. Inserts Cloudflare-only allow rules
5. Generates Nginx real IP configuration
6. Validates configuration with nginx -t
7. Reloads Nginx safely

## 🧠 Nginx Real IP

### The script generates:

```bash
/etc/nginx/conf.d/00-cloudflare_realip.conf
```

### It configures:

```bash
real_ip_header CF-Connecting-IP;
real_ip_recursive on;
set_real_ip_from <Cloudflare IP ranges>;
```

### This ensures:
* Correct visitor IP logging
* Proper rate limiting
* Accurate application logging

## 📄 Verify After Installation
### Check firewall status:

```bash
sudo ufw status verbose
```
Expected:
```bash
Default: deny (incoming)
80/tcp  ALLOW IN  <Cloudflare ranges>
443/tcp ALLOW IN  <Cloudflare ranges>
```

### Check Nginx configuration:
```bash
sudo nginx -t
```

## ⚠️ Important
### Make sure:
* Your domain is proxied through Cloudflare (orange cloud enabled)
* SSH (port 22) remains allowed
* Default UFW policy is:
```bash
Default: deny (incoming)
```

## 🎯 Ideal For
* SaaS backends
* API servers
* Production VPS
* Self-hosted applications behind Cloudflare
* Hardened origin infrastructure

## Versioning
Current version is stored in:
```bash
VERSION
```

## 📜 License
Private infrastructure toolkit.
Use responsibly in production environments.
