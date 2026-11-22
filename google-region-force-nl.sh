#!/usr/bin/env bash
# Google Region Force NL v2.1 - conservative diagnostics and optional settings
set -Eeuo pipefail
VERSION="2.2"
BACKUP_DIR="/root/google-region-fix-backups"
LOG_FILE="/var/log/google-region-fix.log"
DNS_DROPIN="/etc/systemd/resolved.conf.d/90-google-region-fix.conf"
IPV6_FILE="/etc/sysctl.d/99-google-region-fix-ipv6.conf"
need_root(){ [[ ${EUID:-$(id -u)} -eq 0 ]] || { echo 'Run as root (sudo).' >&2; exit 1; }; }
need_root
mkdir -p "$BACKUP_DIR"; touch "$LOG_FILE"
exec > >(tee -a "$LOG_FILE") 2>&1
pause(){ read -r -p $'\nPress Enter to continue...' _ || true; }
header(){ clear 2>/dev/null || true; echo '========================================'; echo " GOOGLE REGION FORCE NL v$VERSION"; echo ' Target: Netherlands (NL)'; echo '========================================'; }
check_deps(){ local missing=() cmd; for cmd in curl ip getent awk sysctl tee timedatectl; do command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd"); done; (("${#missing[@]}")) && { echo "Missing: ${missing[*]}"; return 1; } || true; }
backup(){ local stamp dest f; stamp=$(date +%Y%m%d-%H%M%S)-$$; dest="$BACKUP_DIR/$stamp"; mkdir -p "$dest"; for f in /etc/resolv.conf /etc/systemd/resolved.conf /etc/systemd/resolved.conf.d /etc/sysctl.conf /etc/sysctl.d; do [[ -e "$f" ]] && cp -a "$f" "$dest/"; done; resolvectl status >"$dest/resolvectl-status.txt" 2>&1 || true; sysctl net.ipv6.conf.all.disable_ipv6 net.ipv6.conf.default.disable_ipv6 >"$dest/ipv6-sysctl.txt" 2>&1 || true; timedatectl >"$dest/timedatectl.txt" 2>&1 || true; printf '%s\n' "$dest" >"$BACKUP_DIR/latest"; echo "Backup: $dest"; }
country(){ local label="$1" family="$2" url="$3" result; result=$(curl "$family" -fsS --max-time 10 "$url" 2>/dev/null || true); result=${result//$'\n'/}; if [[ -n "$result" ]]; then echo "$label: $result"; else echo "$label: unavailable"; fi; }
geo_check(){ echo '--- IP / GeoIP checks (multiple providers) ---'; country 'IPv4 ipinfo country' -4 https://ipinfo.io/country; country 'IPv4 ipapi country' -4 https://ipapi.co/country/; country 'IPv4 ipinfo JSON' -4 https://ipinfo.io/json; country 'IPv6 ipinfo country' -6 https://ipinfo.io/country; country 'IPv6 ipapi country' -6 https://ipapi.co/country/; }
compare_nl(){ echo '--- Country comparison against target NL ---'; local result; result=$(curl -4fsS --max-time 10 https://ipinfo.io/country 2>/dev/null || true); result=${result//$'\n'/}; if [[ "$result" == NL ]]; then echo 'IPv4 GeoIP: NL ✓'; else echo "IPv4 GeoIP: ${result:-unknown}"; fi; result=$(curl -6fsS --max-time 10 https://ipinfo.io/country 2>/dev/null || true); result=${result//$'\n'/}; [[ "$result" == NL ]] && echo 'IPv6 GeoIP: NL' || echo "IPv6 GeoIP: ${result:-unavailable/no conclusion}"; echo 'IP geolocation is not a guarantee of Google region/account eligibility.'; }
dns_tests(){ echo '--- DNS resolution ---'; for d in google.com accounts.google.com gemini.google.com youtube.com googleapis.com gstatic.com googlevideo.com; do printf '%-25s ' "$d"; getent ahostsv4 "$d" 2>/dev/null | awk 'NR==1{print $1}' || echo 'resolution failed'; done; }
https_tests(){ echo '--- HTTPS tests (IPv4) ---'; local u code; for u in https://www.google.com/ https://accounts.google.com/ https://gemini.google.com/ https://www.youtube.com/ https://www.googleapis.com/ https://www.gstatic.com/; do code=$(curl -4 -sS -o /dev/null -w '%{http_code} %{remote_ip} %{time_total}s' --max-time 12 "$u" 2>&1 || true); printf '%-34s %s\n' "$u" "$code"; done; }
diagnostics(){ check_deps || return 1; echo '--- IP / GeoIP ---'; geo_check; echo '--- Routing ---'; ip -4 route || true; ip -6 route || true; echo '--- Interfaces ---'; ip -br addr || true; echo '--- IPv6 sysctl ---'; sysctl net.ipv6.conf.all.disable_ipv6 net.ipv6.conf.default.disable_ipv6 2>/dev/null || true; echo '--- DNS / resolved ---'; cat /etc/resolv.conf 2>/dev/null || true; resolvectl status 2>/dev/null || true; dns_tests; https_tests; echo '--- Clock / timezone ---'; timedatectl 2>/dev/null || true; echo '--- Locale ---'; locale 2>/dev/null || true; compare_nl; echo '--- managed override state ---'; [[ -f "$DNS_DROPIN" ]] && echo "Managed DNS file: $DNS_DROPIN" || echo 'No managed DNS override'; [[ -f "$IPV6_FILE" ]] && echo "Managed IPv6 policy: $IPV6_FILE" || echo 'No managed IPv6 policy'; }
dns_fix(){ echo 'Choose DNS resolver:'; echo '1) Cloudflare  2) Google DNS  3) Quad9  4) OpenDNS'; read -r -p 'Choice [1-4]: ' choice; local dns1 dns2; case "$choice" in 1) dns1=1.1.1.1;dns2=1.0.0.1;; 2) dns1=8.8.8.8;dns2=8.8.4.4;; 3) dns1=9.9.9.9;dns2=149.112.112.112;; 4) dns1=208.67.222.222;dns2=208.67.220.220;; *) echo 'Invalid choice';return 1;; esac; systemctl is-active --quiet systemd-resolved || { echo 'systemd-resolved inactive; no change.';return 1; }; backup; mkdir -p /etc/systemd/resolved.conf.d; cat >"$DNS_DROPIN" <<EOF
[Resolve]
DNS=$dns1 $dns2
FallbackDNS=
DNSOverTLS=no
DNSSEC=no
EOF
systemctl restart systemd-resolved; resolvectl status || true; echo "DNS override written: $DNS_DROPIN"; }
ipv6_status(){ echo '--- IPv6 ---'; sysctl net.ipv6.conf.all.disable_ipv6 net.ipv6.conf.default.disable_ipv6 2>/dev/null || true; ip -6 addr || true; ip -6 route || true; country 'IPv6 country' -6 https://ipinfo.io/country; }
ipv6_disable(){ echo 'WARNING: may affect VPNs, Docker and network services.'; read -r -p 'Type DISABLE to continue: ' confirm; [[ "$confirm" == DISABLE ]] || { echo Cancelled;return; }; backup; cat >"$IPV6_FILE" <<'SYS'
net.ipv6.conf.all.disable_ipv6=1
net.ipv6.conf.default.disable_ipv6=1
SYS
sysctl -p "$IPV6_FILE"; }
ipv6_enable(){ backup; rm -f "$IPV6_FILE"; sysctl -w net.ipv6.conf.all.disable_ipv6=0 >/dev/null || true; sysctl -w net.ipv6.conf.default.disable_ipv6=0 >/dev/null || true; echo 'Removed managed IPv6-disable policy; other settings may still control IPv6.'; }
timezone_nl(){ echo 'Current timezone:'; timedatectl; read -r -p 'Set timezone to Europe/Amsterdam? [y/N] ' yn; [[ "$yn" =~ ^[Yy]$ ]] || return; backup; timedatectl set-timezone Europe/Amsterdam; timedatectl; }
restore(){ if [[ -f "$BACKUP_DIR/latest" ]]; then local dir; dir=$(cat "$BACKUP_DIR/latest"); echo "Backup: $dir"; find "$dir" -maxdepth 3 -type f -print || true; else echo 'No backup found.'; fi; read -r -p 'Remove this tool DNS and IPv6 overrides? [y/N] ' yn; if [[ "$yn" =~ ^[Yy]$ ]]; then backup; rm -f "$DNS_DROPIN" "$IPV6_FILE"; systemctl restart systemd-resolved 2>/dev/null || true; sysctl -w net.ipv6.conf.all.disable_ipv6=0 >/dev/null || true; sysctl -w net.ipv6.conf.default.disable_ipv6=0 >/dev/null || true; echo 'Managed overrides removed.'; fi; }
persistence_check(){ echo '--- Persistence / boot readiness ---'; systemctl is-enabled google-region-force-nl-guardian.timer 2>/dev/null || true; systemctl is-active google-region-force-nl-guardian.timer 2>/dev/null || true; systemctl list-timers google-region-force-nl-guardian.timer --no-pager 2>/dev/null || true; systemctl status google-region-force-nl-guardian.service --no-pager 2>/dev/null || true; echo 'Managed files:'; ls -l "$DNS_DROPIN" "$IPV6_FILE" 2>/dev/null || echo 'No managed overrides'; echo 'Netplan/cloud-init/VPN settings are not changed by this tool.'; }
menu(){ while true; do header; echo '1) Full diagnostics';echo '2) Compare IP country with NL';echo '3) IPv6 diagnostics';echo '4) Set DNS persistently';echo '5) Disable IPv6 (persistent/reversible)';echo '6) Re-enable IPv6';echo '7) Set timezone to Amsterdam';echo '8) Review backups/remove overrides';echo '9) Show log';echo '10) Verify reboot persistence / Guardian';echo '0) Exit';read -r -p 'Select: ' opt;case "$opt" in 1) diagnostics;pause;;2) compare_nl;pause;;3) ipv6_status;pause;;4) dns_fix;pause;;5) ipv6_disable;pause;;6) ipv6_enable;pause;;7) timezone_nl;pause;;8) restore;pause;;9) tail -100 "$LOG_FILE";pause;;10) persistence_check;pause;;0) exit 0;;*) echo Invalid;pause;;esac;done; }
check_deps;menu
