#!/usr/bin/env bash
# Google Region Force NL v2.0 - Ubuntu 24.04+
# Network diagnostics and optional persistent DNS / IPv6 configuration.
set -Eeuo pipefail

VERSION="2.0"
BACKUP_DIR="/root/google-region-fix-backups"
LOG_FILE="/var/log/google-region-fix.log"
DNS_DROPIN="/etc/systemd/resolved.conf.d/90-google-region-fix.conf"
IPV6_FILE="/etc/sysctl.d/99-google-region-fix-ipv6.conf"

need_root(){
  if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
    echo 'Run as root: sudo bash google-region-force-nl.sh' >&2; exit 1
  fi
}
need_root
mkdir -p "$BACKUP_DIR"
touch "$LOG_FILE"
exec > >(tee -a "$LOG_FILE") 2>&1

pause(){ read -r -p $'\nPress Enter to continue...' _ || true; }
header(){ clear 2>/dev/null || true; echo '========================================'; echo " GOOGLE REGION FORCE NL v$VERSION"; echo ' Target: Netherlands (NL)'; echo '========================================'; }
check_deps(){
  local missing=() cmd
  for cmd in curl ip getent awk sysctl tee; do command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd"); done
  if ((${#missing[@]})); then echo "Missing commands: ${missing[*]}"; return 1; fi
}
backup(){
  local stamp dest f
  stamp=$(date +%Y%m%d-%H%M%S)-$$; dest="$BACKUP_DIR/$stamp"; mkdir -p "$dest"
  for f in /etc/resolv.conf /etc/systemd/resolved.conf /etc/systemd/resolved.conf.d /etc/sysctl.conf /etc/sysctl.d; do
    if [[ -e "$f" ]]; then cp -a "$f" "$dest/"; fi
  done
  command -v resolvectl >/dev/null 2>&1 && resolvectl status > "$dest/resolvectl-status.txt" 2>&1 || true
  sysctl net.ipv6.conf.all.disable_ipv6 net.ipv6.conf.default.disable_ipv6 > "$dest/ipv6-sysctl.txt" 2>&1 || true
  printf '%s\n' "$dest" > "$BACKUP_DIR/latest"
  echo "Backup created: $dest"
}
geo_check(){
  check_deps || return 1
  echo '--- IPv4 GeoIP (ipinfo) ---'; curl -4fsS --max-time 10 https://ipinfo.io/json || echo 'IPv4 lookup failed'
  echo; echo '--- IPv4 GeoIP (ipapi) ---'; curl -4fsS --max-time 10 https://ipapi.co/json/ || echo 'ipapi lookup failed'
  echo; echo '--- IPv6 GeoIP ---'; curl -6fsS --max-time 10 https://ipinfo.io/json || echo 'IPv6 unavailable or lookup failed'; echo
}
compare_nl(){
  echo '--- Country comparison against target NL ---'
  local result v6
  result=$(curl -4fsS --max-time 10 https://ipinfo.io/country 2>/dev/null || true); result=${result//$'\n'/}
  if [[ "$result" == "NL" ]]; then echo 'IPv4 GeoIP reports NL.'; else echo "IPv4 GeoIP reports '${result:-unknown}', not NL (or lookup unavailable)."; fi
  v6=$(curl -6fsS --max-time 10 https://ipinfo.io/country 2>/dev/null || true); v6=${v6//$'\n'/}
  if [[ "$v6" == "NL" ]]; then echo 'IPv6 GeoIP reports NL.'; elif [[ -n "$v6" ]]; then echo "IPv6 GeoIP reports '$v6' (not NL)."; else echo 'IPv6 unavailable; no conclusion.'; fi
  echo 'Google may also use account, cookies, device location and its own IP classification.'
}
diagnostics(){
  check_deps || return 1
  echo '--- Country / IP ---'; geo_check
  echo '--- Routing ---'; ip -4 route || true; ip -6 route || true
  echo '--- Interfaces ---'; ip -br addr || true
  echo '--- IPv6 sysctl ---'; sysctl net.ipv6.conf.all.disable_ipv6 net.ipv6.conf.default.disable_ipv6 2>/dev/null || true
  echo '--- DNS configuration ---'; cat /etc/resolv.conf 2>/dev/null || true
  command -v resolvectl >/dev/null 2>&1 && resolvectl status || true
  echo '--- DNS resolution ---'; for d in google.com accounts.google.com gemini.google.com youtube.com googleapis.com; do echo "[$d]"; getent ahosts "$d" 2>/dev/null | awk 'NR<=5' || true; done
  echo '--- Google HTTPS checks (IPv4) ---'; for u in https://www.google.com/ https://accounts.google.com/ https://gemini.google.com/ https://www.youtube.com/ https://www.googleapis.com/; do echo "$u"; curl -4 -sS -o /dev/null -D - --max-time 10 "$u" 2>&1 | awk 'NR<=5' || true; done
  echo '--- System locale/time ---'; timedatectl 2>/dev/null || true; locale 2>/dev/null || true
  compare_nl
}
dns_fix(){
  echo 'Choose DNS resolver (persistent systemd-resolved configuration):'
  echo '1) Cloudflare  2) Google DNS  3) Quad9  4) OpenDNS'
  read -r -p 'Choice [1-4]: ' choice
  local dns1 dns2
  case "$choice" in 1) dns1=1.1.1.1; dns2=1.0.0.1;; 2) dns1=8.8.8.8; dns2=8.8.4.4;; 3) dns1=9.9.9.9; dns2=149.112.112.112;; 4) dns1=208.67.222.222; dns2=208.67.220.220;; *) echo 'Invalid choice'; return 1;; esac
  if ! command -v resolvectl >/dev/null 2>&1 || ! systemctl is-active --quiet systemd-resolved; then echo 'systemd-resolved inactive; no changes made.'; return 1; fi
  backup
  mkdir -p /etc/systemd/resolved.conf.d
  cat > "$DNS_DROPIN" <<DNS
[Resolve]
DNS=$dns1 $dns2
FallbackDNS=
DNSOverTLS=no
DNSSEC=no
DNS
  systemctl restart systemd-resolved
  if systemctl is-active --quiet systemd-resolved; then
    echo "Persistent DNS set to $dns1 $dns2 via $DNS_DROPIN"
    resolvectl status || true
    echo 'This persists across reboot while systemd-resolved remains enabled; other network/VPN DNS policies may override it.'
  else echo 'systemd-resolved restart failed. Review log and backup.'; return 1; fi
}
ipv6_status(){ echo '--- IPv6 state ---'; sysctl net.ipv6.conf.all.disable_ipv6 net.ipv6.conf.default.disable_ipv6 2>/dev/null || true; ip -6 addr || true; ip -6 route || true; curl -6fsS --max-time 10 https://ipinfo.io/json || echo 'No working IPv6 lookup'; }
ipv6_disable(){
  echo 'WARNING: global IPv6 disable may affect VPNs, Docker, and services.'; read -r -p 'Type DISABLE to continue: ' confirm; [[ "$confirm" == DISABLE ]] || { echo 'Cancelled'; return; }
  backup
  cat > "$IPV6_FILE" <<'SYS'
net.ipv6.conf.all.disable_ipv6=1
net.ipv6.conf.default.disable_ipv6=1
SYS
  sysctl -p "$IPV6_FILE"
  echo "Persistent IPv6 disable saved in $IPV6_FILE (applies at boot). Reboot not required for current values."
}
ipv6_enable(){
  backup
  rm -f "$IPV6_FILE"
  sysctl -w net.ipv6.conf.all.disable_ipv6=0 >/dev/null || true
  sysctl -w net.ipv6.conf.default.disable_ipv6=0 >/dev/null || true
  echo 'Script IPv6-disable file removed; values set to enabled. Other sysctl files may still override.'
}
restore(){
  if [[ -f "$BACKUP_DIR/latest" ]]; then
    local dir; dir=$(cat "$BACKUP_DIR/latest")
    echo "Backup directory: $dir"; find "$dir" -maxdepth 3 -type f -print || true
    echo 'Restore is deliberately manual to avoid overwriting files managed by Netplan, cloud-init, VPNs, or the OS.'
  else echo 'No backup found.'; fi
  read -r -p 'Remove this tool DNS and IPv6 overrides? [y/N] ' yn
  if [[ "$yn" =~ ^[Yy]$ ]]; then
    backup
    rm -f "$DNS_DROPIN" "$IPV6_FILE"
    systemctl restart systemd-resolved 2>/dev/null || true
    sysctl -w net.ipv6.conf.all.disable_ipv6=0 >/dev/null || true
    sysctl -w net.ipv6.conf.default.disable_ipv6=0 >/dev/null || true
    echo 'Tool overrides removed. Other system/network-manager settings may still apply.'
  fi
}
menu(){
  while true; do
    header
    echo '1) Full diagnostics'; echo '2) Compare IP country with NL target'; echo '3) IPv6 diagnostics'; echo '4) Set DNS persistently'; echo '5) Disable IPv6 globally (persistent/reversible)'; echo '6) Re-enable IPv6'; echo '7) Review backups / restore overrides'; echo '8) Show log'; echo '0) Exit'
    read -r -p 'Select: ' opt
    case "$opt" in 1) diagnostics; pause;; 2) compare_nl; pause;; 3) ipv6_status; pause;; 4) dns_fix; pause;; 5) ipv6_disable; pause;; 6) ipv6_enable; pause;; 7) restore; pause;; 8) tail -100 "$LOG_FILE"; pause;; 0) exit 0;; *) echo 'Invalid option'; pause;; esac
  done
}
check_deps
menu
