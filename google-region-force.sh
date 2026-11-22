#!/usr/bin/env bash
set -Eeuo pipefail
VERSION="3.1.0"
CFG=/etc/google-region-force.conf
LOG=/var/log/google-region-force.log
BACK=/root/google-region-force-backups
DNS=/etc/systemd/resolved.conf.d/90-google-region-force.conf
mkdir -p "$BACK"; touch "$LOG"
exec > >(tee -a "$LOG") 2>&1
TARGET=NL; TZ_TARGET=Europe/Amsterdam
if [[ -f "$CFG" ]]; then source "$CFG"; fi
TARGET=${TARGET:-NL}; TZ_TARGET=${TZ_TARGET:-Europe/Amsterdam}
root(){ [[ $EUID -eq 0 ]] || { echo 'Run as root.'; exit 1; }; }
pause(){ read -r -p 'Press Enter...' _ || true; }
backup(){ local d="$BACK/$(date +%Y%m%d-%H%M%S)"; mkdir -p "$d"; for f in /etc/resolv.conf /etc/systemd/resolved.conf "$DNS" "$CFG"; do [[ -e "$f" ]] && cp -a --parents "$f" "$d/" || true; done; resolvectl status >"$d/resolved.txt" 2>&1 || true; timedatectl >"$d/time.txt" 2>&1 || true; echo "$d" >"$BACK/latest"; echo "Backup created: $d"; }
save(){ printf 'TARGET="%s"\nTZ_TARGET="%s"\n' "$TARGET" "$TZ_TARGET" > "$CFG"; chmod 600 "$CFG"; }
header(){ clear 2>/dev/null || true; echo "Google Region Force PRO v$VERSION"; echo "Target: $TARGET | timezone: $TZ_TARGET"; }
country(){ local fam="$1" url="$2"; curl "$fam" -fsS --max-time 10 "$url" 2>/dev/null | tr -d '[:space:]' || true; }
geo_one(){ local fam="$1" label="$2" c; c=$(country "$fam" https://ipinfo.io/country); [[ -n "$c" ]] || c='unavailable'; echo "$label ipinfo: $c"; local d; d=$(country "$fam" https://ipapi.co/country/); [[ -n "$d" ]] || d='unavailable'; echo "$label ipapi: $d"; }
geo(){ geo_one -4 IPv4; geo_one -6 IPv6; echo 'IPv4 detail:'; curl -4 -fsS --max-time 10 https://ipinfo.io/json || echo 'ipinfo unavailable'; echo; }
compare(){ local c fam label; for fam in -4 -6; do label=IPv4; [[ "$fam" == -6 ]] && label=IPv6; c=$(country "$fam" https://ipinfo.io/country); [[ -n "$c" ]] || c=unavailable; if [[ "$c" == "$TARGET" ]];then echo "$label: MATCH ($c)";elif [[ "$c" == unavailable ]];then echo "$label: UNKNOWN (source unavailable)";else echo "$label: MISMATCH — detected $c, target $TARGET";fi;done;echo 'GeoIP is not Google geolocation; Google may use additional signals.'; }
dns(){ for d in google.com accounts.google.com gemini.google.com youtube.com googleapis.com gstatic.com googlevideo.com; do echo "-- $d"; getent ahostsv4 "$d" | awk '!seen[$1]++{print $1;exit}' || true; done; resolvectl status 2>&1 || true; }
https(){ for u in https://www.google.com/ https://accounts.google.com/ https://gemini.google.com/ https://www.youtube.com/ https://www.googleapis.com/ https://www.gstatic.com/; do curl -4 -sS -o /dev/null -w "$u HTTP %{http_code} | IP %{remote_ip} | %{time_total}s\n" --max-time 12 "$u" || true; done; }
route_test(){ for host in www.google.com accounts.google.com gemini.google.com youtube.com; do echo "-- Route to $host"; local ip; ip=$(getent ahostsv4 "$host" | awk 'NR==1{print $1}'); if [[ -n "$ip" ]];then ip route get "$ip" 2>&1 || true;else echo 'DNS resolution failed';fi; done; }
diagnostics(){ echo '=== GeoIP ===';geo;echo '=== Routes ===';ip -4 route;ip -6 route || true;route_test;echo '=== Interfaces ===';ip -br addr;echo '=== IPv6 sysctl ===';sysctl net.ipv6.conf.all.disable_ipv6 net.ipv6.conf.default.disable_ipv6 2>&1||true;echo '=== DNS file ===';cat /etc/resolv.conf 2>&1||true;echo '=== DNS queries ===';dns;echo '=== HTTPS ===';https;echo '=== Clock ===';timedatectl 2>&1||true;echo '=== Locale ===';locale 2>&1||true;echo '=== Managed DNS file ===';if [[ -f "$DNS" ]];then cat "$DNS";else echo 'Not installed';fi;echo '=== GeoIP comparison ===';compare; }
settarget(){ read -r -p 'Target country ISO code (e.g. SE, NL, DE, FI, US): ' c; c=$(printf '%s' "$c"|tr '[:lower:]' '[:upper:]');[[ "$c" =~ ^[A-Z]{2}$ ]] || { echo 'Invalid country code';return;};read -r -p 'Timezone (e.g. Europe/Stockholm): ' z; if [[ -n "$z" ]] && ! timedatectl list-timezones | grep -Fxq "$z";then echo 'Invalid timezone';return;fi;TARGET=$c;[[ -n "$z" ]] && TZ_TARGET=$z;save;echo "Saved target $TARGET / $TZ_TARGET"; }
dnsset(){ echo '1 Cloudflare  2 Google  3 Quad9  4 OpenDNS';read -r -p 'Choice: ' n;case "$n" in 1)a='1.1.1.1 1.0.0.1';;2)a='8.8.8.8 8.8.4.4';;3)a='9.9.9.9 149.112.112.112';;4)a='208.67.222.222 208.67.220.220';;*)echo 'Cancelled';return;;esac;systemctl is-active --quiet systemd-resolved || { echo 'systemd-resolved is not active; no changes made';return;};backup;mkdir -p /etc/systemd/resolved.conf.d;printf '[Resolve]\nDNS=%s\nFallbackDNS=\nDNSOverTLS=no\nDNSSEC=no\n' "$a" >"$DNS";systemctl restart systemd-resolved;resolvectl status; }
ipv6(){ echo 'IPv6 sysctl:';sysctl net.ipv6.conf.all.disable_ipv6 net.ipv6.conf.default.disable_ipv6 2>&1||true;echo 'IPv6 addresses:';ip -6 addr;echo 'IPv6 routes:';ip -6 route||true;echo 'IPv6 GeoIP:';geo_one -6 IPv6; }
tzset(){ if timedatectl list-timezones | grep -Fxq "$TZ_TARGET";then backup;timedatectl set-timezone "$TZ_TARGET";timedatectl;else echo "Timezone unavailable: $TZ_TARGET";fi; }
restore_dns(){ read -r -p 'Remove ONLY managed DNS override and restart resolved? [y/N] ' y;if [[ "$y" =~ ^[Yy]$ ]];then backup;rm -f "$DNS";systemctl restart systemd-resolved||true;echo 'Managed DNS override removed. Other resolver settings were not changed.';fi; }
google_region_analyzer(){
  local REPORT="/root/google-region-report.txt"
  local TMP="/tmp/google-region-force-analyzer"
  mkdir -p "$TMP"
  analyzer_core(){
    echo "===== GOOGLE REGION ANALYZER PRO v3.1 ====="
    echo "Date: $(date -Is)"
    echo "--- Public IP / GeoIP signals ---"
    for fam in -4 -6; do
      local label; label=IPv4; [[ "$fam" == -6 ]] && label=IPv6
      echo "[$label]"
      for url in https://ipinfo.io/country https://ipapi.co/country/ https://ifconfig.co/country-iso; do
        printf '%s: ' "$url"
        local val; val=$(curl "$fam" -fsS --max-time 8 "$url" 2>/dev/null | tr -d '[:space:]' || true)
        echo "${val:-unavailable}"
      done
      printf 'Public IP: '
      local ip; ip=$(curl "$fam" -fsS --max-time 8 https://api.ipify.org 2>/dev/null || true)
      echo "${ip:-unavailable}"
    done
    echo "--- DNS ---"
    for host in google.com www.google.com accounts.google.com gemini.google.com youtube.com googleapis.com googlevideo.com gstatic.com; do
      printf '%-24s ' "$host"
      getent ahostsv4 "$host" | awk '!seen[$1]++{print $1}' | paste -sd ',' || true
    done
    echo "--- HTTP checks ---"
    local urls=(
      "https://www.google.com/"
      "https://www.google.com/?hl=en"
      "https://www.google.com/?hl=en&gl=NL"
      "https://www.google.com/?hl=en&gl=BG"
      "https://www.google.com/?hl=en&gl=RU"
      "https://accounts.google.com/"
      "https://gemini.google.com/"
      "https://www.youtube.com/"
      "https://www.googleapis.com/"
      "https://generativelanguage.googleapis.com/"
    )
    for url in "${urls[@]}"; do
      curl -4 -sS -L -o "$TMP/body.html" -D "$TMP/headers.txt" --max-time 15 -w "$url | HTTP %{http_code} | IP %{remote_ip} | %{time_total}s\n" "$url" || true
      grep -iE '^(HTTP/|location:|content-language:|x-country:|x-region:)' "$TMP/headers.txt" | tail -6 || true
      if [[ "$url" == *"google.com/?hl=en"* ]]; then
        grep -Eo '<html[^>]*>|<title>[^<]{0,120}</title>' "$TMP/body.html" | head -3 || true
      fi
    done
    echo "--- Locale hints (html lang/title only) ---"
    for url in "https://www.google.com/" "https://www.google.com/?hl=en&gl=NL" "https://www.google.com/?hl=en&gl=BG" "https://www.google.com/?hl=en&gl=RU"; do
      echo "$url"
      curl -4 -sS -L --max-time 12 "$url" 2>/dev/null | grep -Eo '<html[^>]*>|<title>[^<]{0,120}</title>' | head -3 || true
    done
    echo "--- Route / DNS configuration ---"
    ip -4 route; ip -6 route 2>/dev/null || true
    resolvectl status 2>/dev/null | sed -n '1,40p' || true
    echo "--- IP registration (best effort) ---"
    if command -v whois >/dev/null 2>&1; then whois "$(curl -4 -fsS --max-time 8 https://api.ipify.org 2>/dev/null || true)" | head -45; else echo "whois utility not installed; skipped"; fi
    echo "--- Interpretation ---"
    echo "Locale (lang) and gl parameter are not proof of IP country. GeoIP providers may disagree."
    echo "Google API root HTTP 404 is not an API functionality test; API requests commonly require credentials."
  }
  analyzer_core | tee "$REPORT"
  echo "Report saved: $REPORT"
}
showlog(){ echo '--- last 100 log lines (not re-logged) ---';tail -100 "$LOG" | sed 's/^/[LOG] /'; }
menu(){ root;while true;do header;echo '1) Full diagnostics';echo '2) Change target country/timezone';echo '3) Compare GeoIP with target';echo '4) DNS diagnostics';echo '5) Set DNS (persistent)';echo '6) IPv6 diagnostics';echo '7) Set target timezone';echo '8) Remove managed DNS override';echo '9) Show log';echo '10) Google Region Analyzer';echo '0) Exit';read -r -p 'Select: ' o;case "$o" in 1)diagnostics;pause;;2)settarget;pause;;3)compare;pause;;4)dns;pause;;5)dnsset;pause;;6)ipv6;pause;;7)tzset;pause;;8)restore_dns;pause;;9)showlog;pause;;10)google_region_analyzer;pause;;0)exit;;*)echo 'Invalid option';pause;;esac;done;}
menu
