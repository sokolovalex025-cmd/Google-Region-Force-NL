# Google Region Force NL

Persistent, conservative DNS/IPv6 configuration helper for Ubuntu 24.04+. This tool **cannot guarantee** Google's detected region: Google may use account settings, browser cookies, location signals and its own GeoIP data.

## Features
- interactive DNS selection using `systemd-resolved` drop-in
- optional reversible IPv6 disable (warning: may impact VPNs, Docker and other services)
- backups, diagnostics, and removal of this tool's overrides
- systemd boot verifier/guardian: checks the tool's DNS override and reapplies the IPv6 sysctl file if present; it does not rewrite routing, firewall, Netplan, VPN or DNS settings

## Install (one command)
```bash
curl -fsSL https://raw.githubusercontent.com/sokolovalex025-cmd/Google-Region-Force-NL/main/install.sh | sudo bash
```

## Run
```bash
sudo google-region-force-nl
```

## Guardian
```bash
systemctl status google-region-force-nl-guardian.service
journalctl -u google-region-force-nl-guardian.service
```
A timer runs at boot and daily. The guardian only verifies managed files and applies the managed IPv6 sysctl file if one exists; it does not silently disable IPv6 or change DNS selection.

## Uninstall
```bash
sudo bash uninstall.sh
```
Uninstall removes the systemd guardian and launcher, but leaves DNS/sysctl overrides intact until removed through the tool's menu. This is deliberate to avoid unexpected network changes.
