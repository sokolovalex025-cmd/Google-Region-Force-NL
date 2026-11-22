# Google Region Force NL v2.1

Conservative Ubuntu 24.04+ diagnostic/configuration helper. It cannot guarantee Google's detected region or eligibility.

## Features
- Multi-provider IPv4/IPv6 country checks (best effort; providers may rate-limit).
- DNS checks for Google, Gemini, YouTube, Google APIs, Googlevideo and Gstatic.
- IPv4 HTTP reachability checks with status, remote IP and timing.
- Persistent DNS options through systemd-resolved.
- Optional IPv6 sysctl policy with backup and confirmation.
- Optional Europe/Amsterdam timezone setting (backup + confirmation).
- Guardian quick checks at boot and daily; it logs health information and only reapplies this tool's explicit IPv6 policy.
- Does not modify routes, firewall, Netplan, cloud-init, Docker, Xray, AntiZapret or VPN configuration.

## Install
```bash
curl -fsSL https://raw.githubusercontent.com/sokolovalex025-cmd/Google-Region-Force-NL/main/install.sh | sudo bash
```

## Run
```bash
sudo google-region-force-nl
```

Menu includes Full diagnostics, IP-country comparison, IPv6 diagnostics, DNS, IPv6 controls, Amsterdam timezone, backups and log.

## Guardian
```bash
systemctl status google-region-force-nl-guardian.timer
journalctl -u google-region-force-nl-guardian.service
tail -100 /var/log/google-region-force-nl-guardian.log
```

The guardian is a diagnostic helper, not a routing watchdog. GeoIP services can rate-limit or disagree. HTTP 200 indicates reachability, not account-region eligibility.

## Uninstall
Use the project's uninstall script. DNS and IPv6 managed overrides remain until removed using the tool's menu, by design.
