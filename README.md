# Google Region Force NL v2.2

Persistent, conservative diagnostic/configuration helper for Ubuntu 24.04+. It cannot guarantee Google's detected region.

## Persistence
- The installer enables the systemd timer.
- Guardian runs about 90 seconds after boot and daily.
- DNS/IPv6 overrides are stored in managed configuration files and persist until removed.
- Guardian checks connectivity and reapplies only this tool's explicit IPv6 policy.
- Menu option 10 verifies timer/service persistence.

## Features
- Multi-provider country checks, best effort.
- Google/Gemini/YouTube DNS and HTTP checks.
- DNS selection via systemd-resolved.
- Optional IPv6 sysctl policy.
- Optional Europe/Amsterdam timezone.
- Backups and managed override removal.
- Does not change routes, firewall, Netplan, cloud-init, Docker, Xray, AntiZapret or VPN settings.

## Install
```bash
curl -fsSL https://raw.githubusercontent.com/sokolovalex025-cmd/Google-Region-Force-NL/main/install.sh | sudo bash
```

## Run
```bash
sudo google-region-force-nl
```

## Persistence verification
```bash
systemctl is-enabled google-region-force-nl-guardian.timer
systemctl list-timers google-region-force-nl-guardian.timer
systemctl status google-region-force-nl-guardian.service
journalctl -u google-region-force-nl-guardian.service --no-pager
```
Use menu option 10 to inspect reboot readiness.

## Uninstall
Run project's uninstall script. Managed DNS/sysctl overrides remain until removed through the menu, intentionally.
