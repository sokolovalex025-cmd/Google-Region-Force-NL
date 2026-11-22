#!/usr/bin/env bash
set -Eeuo pipefail
LOG=/var/log/google-region-force-nl-guardian.log
mkdir -p /var/log
exec >>"$LOG" 2>&1
echo "[$(date -Is)] Guardian v2.2 start"
DNS=/etc/systemd/resolved.conf.d/90-google-region-fix.conf
IPV6=/etc/sysctl.d/99-google-region-fix-ipv6.conf
if [[ -f "$DNS" ]]; then echo 'Managed DNS file exists:'; grep -E '^(DNS|FallbackDNS|DNSOverTLS|DNSSEC)=' "$DNS" || true; systemctl is-active --quiet systemd-resolved && resolvectl status || echo 'WARNING: resolved inactive'; else echo 'No managed DNS override'; fi
if [[ -f "$IPV6" ]]; then echo 'Applying managed IPv6 policy'; sysctl -p "$IPV6" || echo 'WARN: apply failed'; else echo 'No managed IPv6 policy'; fi
echo '--- quick health checks ---'
curl -4 -fsS --max-time 8 https://ipinfo.io/country 2>/dev/null || echo 'IPv4 country lookup failed'
for d in google.com gemini.google.com youtube.com; do getent ahostsv4 "$d" 2>/dev/null | awk -v d="$d" 'NR==1{print d, $1}' || echo "$d resolution failed"; done
for u in https://www.google.com/ https://gemini.google.com/ https://www.youtube.com/; do curl -4 -sS -o /dev/null -w "$u %{http_code} %{time_total}s\n" --max-time 10 "$u" || echo "$u failed"; done
echo "[$(date -Is)] Guardian end"
