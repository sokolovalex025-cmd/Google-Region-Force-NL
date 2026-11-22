#!/usr/bin/env bash
set -Eeuo pipefail
LOG=/var/log/google-region-force-nl-guardian.log
mkdir -p /var/log
exec >>"$LOG" 2>&1
echo "[$(date -Is)] guardian start"
DNS=/etc/systemd/resolved.conf.d/90-google-region-fix.conf
IPV6=/etc/sysctl.d/99-google-region-fix-ipv6.conf
if [[ -f "$DNS" ]]; then
  echo 'Managed DNS drop-in exists.'
  grep -E '^(DNS|FallbackDNS|DNSOverTLS|DNSSEC)=' "$DNS" || true
  if systemctl is-active --quiet systemd-resolved; then resolvectl status || true; else echo 'WARNING: systemd-resolved is not active'; fi
else echo 'DNS override not configured by this tool.'; fi
if [[ -f "$IPV6" ]]; then
  echo 'Applying managed IPv6 sysctl policy file.'
  sysctl -p "$IPV6" || echo 'WARN: sysctl application failed'
else echo 'No managed IPv6 policy file; no IPv6 changes made.'; fi
echo "[$(date -Is)] guardian end"
