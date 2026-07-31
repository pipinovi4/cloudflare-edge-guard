# Changelog

## 2.0.0 - 2026-07-31

### Added

- Two-phase `prepare` and `enforce` workflow plus `update`, `verify`, `status`, and scoped `uninstall`.
- Strict non-executing configuration parser and example configuration.
- Cloudflare CIDR syntax, completeness, HTTPS endpoint, deduplication, and last-known-good checks.
- Transactional, toolkit-tagged UFW management that preserves SSH and unrelated rules.
- Generated reverse proxy, Origin CA TLS, real client IP configuration, backups, locks, logging, and dry-run.
- Systemd update examples, Bats suite, ShellCheck/shfmt/Bash validation, Makefile, and CI.

### Changed

- The legacy updater is now a compatibility wrapper around `edge-guard.sh update` and requires a config file.
- Removed tracked infrastructure-specific Nginx site files and disabled obsolete TLS 1.0/1.1 in the legacy example.
- Automatic updates now prefer systemd timers over cron.

### Security

- Firewall rules are added before old managed rules are removed and rolled back on failure.
- Nginx is never reloaded after a failed `nginx -t`.
- Cloudflare downloads fail closed on empty, malformed, HTML, or suspiciously incomplete responses.

## 1.0.0

- Initial single-script Cloudflare IP, UFW, and Nginx real-IP updater.
