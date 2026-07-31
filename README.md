# Cloudflare Edge Guard

Cloudflare Edge Guard hardens an Ubuntu or Debian Nginx origin behind Cloudflare. It configures a local reverse proxy, restores real visitor IPs, and limits inbound web traffic to Cloudflare's published networks without touching SSH or unrelated UFW rules.

> Firewall changes can cut off a site when DNS, TLS, or the application is wrong. Run `prepare`, verify the site, set Cloudflare to **Full (strict)**, and only then run `enforce`. Keep an existing SSH session open and retain console access during first enforcement.

## Architecture and security model

```text
Registrar -> Cloudflare proxied DNS -> Cloudflare HTTPS edge
          -> VPS static IP :80/:443 -> host Nginx -> 127.0.0.1:8080
```

The application stays bound to loopback. Nginx is the only public web service. UFW permits ports 80/443 only from validated official Cloudflare CIDRs. Rules carry a `cloudflare-edge-guard:<digest>` comment, so the toolkit never deletes SSH, user-created, or unrelated rules. New rules are installed and verified before old managed rules are removed. Fetch or preflight failure leaves the last known-good state intact.

Features include IPv4/IPv6, strict configuration parsing (never `source`/`eval`), Origin CA TLS, Nginx `real_ip`, backups, dry-run, idempotent operations, overlap locks, systemd updates, and isolated automated tests. Ubuntu 22.04 and 24.04 are the primary targets; current Debian releases should work but are not yet exercised in CI.

## Requirements and repository layout

Install `bash`, `curl`, `nginx`, `ufw`, `flock` (util-linux), `getent` (libc-bin), `coreutils`, and `systemd`. The tool installs nothing automatically. Root is required for system changes.

- `edge-guard.sh`: `prepare`, `enforce`, `update`, `verify`, `status`, and `uninstall`
- `lib/`: configuration, download validation, Nginx, firewall, preflight, and logging modules
- `config/edge-guard.env.example`: complete configuration example
- `templates/`: systemd service and timer
- `tests/`: Bats tests and offline fixtures
- `scripts/update_cf_edge.sh`: deprecated compatibility wrapper
- `nginx/` and `cron/`: legacy examples; use generated configuration and systemd for new installs

## Safe end-to-end deployment

Follow this order exactly.

1. Attach a static IP to the VPS (for example Lightsail) and note it as `203.0.113.10`. In the provider firewall, allow SSH from trusted administration addresses and allow TCP 80/443; UFW performs the Cloudflare restriction on the host.
2. Add `example.com` to Cloudflare and review imported records.
3. Replace the registrar's authoritative nameservers with the two assigned by Cloudflare. Wait until Cloudflare marks the zone active.
4. Create proxied (orange-cloud) `A` records for `example.com` and, if wanted, `www`, both pointing at `203.0.113.10`. Add `AAAA` only when the VPS has working public IPv6.
5. Deploy the application on `127.0.0.1:8080`, not `0.0.0.0:8080`, and expose a lightweight `/health` endpoint.
6. In Cloudflare, open **SSL/TLS > Origin Server > Create certificate**. Include `example.com` and `*.example.com` if `www` is enabled. Cloudflare Origin CA keys are credentials: never paste them into this repository.
7. Store the certificate and key securely:

   ```bash
   sudo install -d -m 750 /etc/nginx/ssl
   sudo install -m 644 cloudflare-origin.pem /etc/nginx/ssl/cloudflare-origin.pem
   sudo install -m 600 cloudflare-origin.key /etc/nginx/ssl/cloudflare-origin.key
   ```

8. Install and configure the toolkit:

   ```bash
   sudo install -d -m 755 /usr/local/lib/cloudflare-edge-guard /etc/cloudflare-edge-guard
   sudo cp -a edge-guard.sh lib VERSION /usr/local/lib/cloudflare-edge-guard/
   sudo chmod +x /usr/local/lib/cloudflare-edge-guard/edge-guard.sh
   sudo install -m 600 config/edge-guard.env.example /etc/cloudflare-edge-guard/config.env
   sudoedit /etc/cloudflare-edge-guard/config.env
   ```

9. Preview, then prepare Nginx. `prepare` checks the local health endpoint, obtains and validates ranges for Nginx real-IP configuration, runs `nginx -t`, and reloads only after success. It never restricts UFW.

   ```bash
   sudo /usr/local/lib/cloudflare-edge-guard/edge-guard.sh prepare --config /etc/cloudflare-edge-guard/config.env --dry-run
   sudo /usr/local/lib/cloudflare-edge-guard/edge-guard.sh prepare --config /etc/cloudflare-edge-guard/config.env
   ```

10. Verify the upstream and generated configuration before firewall enforcement:

    ```bash
    curl --fail http://127.0.0.1:8080/health
    sudo nginx -t
    curl -I http://example.com
    curl -I https://example.com
    ```

11. In **Cloudflare > SSL/TLS > Overview**, select **Full (strict)**. Do not use Flexible mode.
12. Ensure UFW is already active and SSH is allowed. Edge Guard deliberately never creates, changes, or removes SSH rules. Then preview and enforce:

    ```bash
    sudo ufw status verbose
    sudo /usr/local/lib/cloudflare-edge-guard/edge-guard.sh enforce --config /etc/cloudflare-edge-guard/config.env --dry-run
    sudo /usr/local/lib/cloudflare-edge-guard/edge-guard.sh enforce --config /etc/cloudflare-edge-guard/config.env
    ```

13. Confirm `https://example.com` works through Cloudflare and run `verify`.
14. Confirm direct-origin HTTP is blocked from a machine outside Cloudflare:

    ```bash
    curl --connect-timeout 5 --resolve example.com:443:203.0.113.10 https://example.com/
    ```

    A timeout is expected after enforcement. Before enforcement, add `--cacert cloudflare-origin.pem` for a deliberate origin TLS test. A normal browser may report an untrusted issuer: Cloudflare Origin CA certificates authenticate origins to Cloudflare, not to public browser trust stores.
15. Enable automatic updates as described below.

## Configuration reference

Configuration is literal `KEY=value`: no quotes, substitutions, shell commands, or inline comments. Keep the live file mode `600`; never put API tokens or private-key contents in it. This tool does not require a Cloudflare API token.

| Key | Meaning |
|---|---|
| `DOMAIN`, `ENABLE_WWW` | Valid public hostname and optional `www` name |
| `UPSTREAM_HOST`, `UPSTREAM_PORT` | Loopback host (`127.0.0.1`, `localhost`, or `::1`) and port |
| `HEALTHCHECK_PATH` | Absolute local health path |
| `ENABLE_NGINX` | Manage the site and real-IP snippets |
| `ENABLE_HTTP_REDIRECT` | Redirect HTTP to HTTPS when origin TLS is enabled |
| `ENABLE_ORIGIN_TLS` | Create the 443 origin server block |
| `ORIGIN_CERT_PATH`, `ORIGIN_KEY_PATH` | Readable certificate and private-key paths; key mode must be 600/640 or tighter |
| `ENABLE_UFW` | Manage only tagged Edge Guard web rules |
| `SSH_PORT` | Validated/documented SSH port; no SSH rule is modified |
| `ENABLE_CLOUDFLARE_EDGE_GUARD` | Enable Cloudflare-only web rules |
| `ENABLE_IPV6` | Include official Cloudflare IPv6 ranges |
| `CLOUDFLARE_IPV4_URL`, `CLOUDFLARE_IPV6_URL` | Must remain the official HTTPS endpoints |
| `ENABLE_AUTOMATIC_UPDATES`, `UPDATE_SCHEDULE` | Installation intent and validated `HH:MM`; timer installation is explicit |
| `LOG_FILE`, `STATE_DIR`, `BACKUP_DIR` | Log, last-known-good ranges/lock, and timestamped backups |
| `DRY_RUN` | Print mutations without executing them |

See [the example configuration](config/edge-guard.env.example) for defaults. `--config PATH`, `--verbose`, and `--dry-run` apply to commands; `--help` and `--version` need no config.

## Operations

```bash
sudo ./edge-guard.sh verify --config /etc/cloudflare-edge-guard/config.env
sudo ./edge-guard.sh status --config /etc/cloudflare-edge-guard/config.env
sudo ./edge-guard.sh update --config /etc/cloudflare-edge-guard/config.env
```

Repeated preparation, enforcement, and updates are idempotent. An unchanged update skips Nginx reload and firewall churn. Backups are written before managed Nginx files are replaced.

Install automatic updates after a successful enforcement:

```bash
sudo install -m 644 templates/cloudflare-edge-guard.service /etc/systemd/system/
sudo install -m 644 templates/cloudflare-edge-guard.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now cloudflare-edge-guard.timer
systemctl list-timers cloudflare-edge-guard.timer
```

Edit `OnCalendar` in the timer if `UPDATE_SCHEDULE` differs from `04:00`; the example timer runs at 04:00 UTC with jitter. The script's own lock also prevents overlap. To update the toolkit, review release notes, replace `/usr/local/lib/cloudflare-edge-guard` while preserving `/etc/cloudflare-edge-guard/config.env`, run `prepare`, then `verify` and `update`.

### Rollback and uninstallation

If Nginx validation fails, it is not reloaded. Restore the newest file from `BACKUP_DIR`, run `sudo nginx -t`, then reload. A failed firewall transaction removes the new digest and retains old managed rules. Console access is the recovery path if a manual UFW change causes loss of access.

```bash
sudo ./edge-guard.sh uninstall --config /etc/cloudflare-edge-guard/config.env --dry-run
sudo ./edge-guard.sh uninstall --config /etc/cloudflare-edge-guard/config.env
sudo systemctl disable --now cloudflare-edge-guard.timer
```

Uninstall removes only tagged UFW rules and managed Nginx files. It preserves SSH rules, unrelated rules, certificates, configuration, state, logs, and backups so deletion remains an explicit administrator decision.

## Troubleshooting

- **521 Web server down:** Nginx is stopped, not listening, or UFW lacks current Cloudflare ranges. Check `systemctl status nginx`, `nginx -t`, and `ufw status`.
- **522 Connection timed out:** provider firewall/routing/UFW blocked Cloudflare, the origin IP is wrong, or the server is overloaded.
- **525 SSL handshake failed:** origin TLS is unavailable or incompatible. Confirm port 443, certificate/key pairing, and TLS 1.2+.
- **526 Invalid SSL certificate:** Full (strict) cannot validate the origin name, dates, or chain. Reissue the Origin CA certificate with all required hostnames.
- **502/504:** Nginx cannot reach `127.0.0.1:8080`; check the application binding and health path.
- **Wrong visitor IP:** confirm `/etc/nginx/conf.d/00-cloudflare-edge-guard-realip.conf` is included and requests actually traverse Cloudflare. Trusting these headers without firewall isolation permits spoofing.
- **IPv6 surprises:** do not publish `AAAA` until origin IPv6 and UFW IPv6 support work; otherwise set `ENABLE_IPV6=false`.

Cloudflare proxy status cannot be proven perfectly from DNS alone because routing and products vary; the command checks resolution and the administrator must confirm the orange-cloud state in the dashboard.

## Development, versioning, and license

Tests use temporary directories and mocks/fixtures; they never invoke the host's real Nginx, UFW, `/etc`, cron, systemd, or network configuration.

```bash
make syntax
make lint
make format-check
make test
make check
```

These require Bash, Bats, ShellCheck, and shfmt. CI runs the same checks without root or live network access. See [CHANGELOG.md](CHANGELOG.md); semantic versions are stored in `VERSION`.

No separate license has been granted yet. Until a `LICENSE` file is added, copyright law reserves all rights; obtain permission before redistribution.
