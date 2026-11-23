#!/usr/bin/env bash
set -Eeuo pipefail
VERSION="3.2.0"
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
dnsset(){ echo '1 Cloudflare  2 Google  3 Quad9  4 OpenDNS';read -r -p 'Choice: ' n;case "$n" in 1)a='1.1.1.1 1.0.0.1';;2)a='8.8.8.8 8.8.4.4';;3)a='9.9.9.9 149.112.112.112';;4)a='208.67.222.222 208.67.220.220';;*)echo 'Cancelled';return;;esac;systemctl is-active --quiet systemd-resolved || { echo 'systemd-resolved is not active; no changes made';return;};backup;mkdir -p /etc/systemd/resolved.conf.d;local old='';[[ -f "$DNS" ]] && old=$(cat "$DNS");printf '[Resolve]\nDNS=%s\nFallbackDNS=\nDNSOverTLS=no\nDNSSEC=no\n' "$a" >"$DNS";if systemctl restart systemd-resolved && resolvectl status >/dev/null 2>&1;then echo 'DNS override applied.';resolvectl status;else echo 'DNS restart failed; restoring previous managed override.';if [[ -n "$old" ]];then printf '%s\n' "$old" >"$DNS";else rm -f "$DNS";fi;systemctl restart systemd-resolved || true;return 1;fi; }
ipv6(){ echo 'IPv6 sysctl:';sysctl net.ipv6.conf.all.disable_ipv6 net.ipv6.conf.default.disable_ipv6 2>&1||true;echo 'IPv6 addresses:';ip -6 addr;echo 'IPv6 routes:';ip -6 route||true;echo 'IPv6 GeoIP:';geo_one -6 IPv6; }
tzset(){ if timedatectl list-timezones | grep -Fxq "$TZ_TARGET";then backup;timedatectl set-timezone "$TZ_TARGET";timedatectl;else echo "Timezone unavailable: $TZ_TARGET";fi; }
restore_dns(){ read -r -p 'Remove ONLY managed DNS override and restart resolved? [y/N] ' y;if [[ "$y" =~ ^[Yy]$ ]];then backup;rm -f "$DNS";systemctl restart systemd-resolved||true;echo 'Managed DNS override removed. Other resolver settings were not changed.';fi; }
google_region_analyzer(){
  local REPORT="/root/google-region-report.txt"
  local TMP
  umask 077
  TMP=$(mktemp -d /tmp/google-region-force-analyzer.XXXXXX) || { echo "Cannot create temporary directory"; return 1; }
  analyzer_core(){
    echo "===== GOOGLE REGION FORCE PRO v3.2.0 | DEEP ANALYZER ====="
    echo "Date: $(date -Is)"
    echo "--- Public IP / GeoIP signals ---"
    local ipv4 ipv6
    ipv4=$(curl -4 -fsS --max-time 8 https://api.ipify.org 2>/dev/null || true)
    ipv6=$(curl -6 -fsS --max-time 8 https://api.ipify.org 2>/dev/null || true)
    echo "IPv4: ${ipv4:-unavailable}"; echo "IPv6: ${ipv6:-unavailable}"
    local signals=0 match=0 mismatch=0
    for fam in -4 -6; do
      local label; label=IPv4; [[ "$fam" == -6 ]] && label=IPv6
      [[ "$fam" == -4 && -z "$ipv4" || "$fam" == -6 && -z "$ipv6" ]] && { echo "[$label] skipped (address unavailable)"; continue; }
      echo "[$label]"
      local provider country
      for provider in ipinfo ipapi ifconfig; do
        case "$provider" in
          ipinfo) country=$(curl "$fam" -fsS --max-time 8 https://ipinfo.io/country 2>/dev/null | tr -d '[:space:]' || true);;
          ipapi) country=$(curl "$fam" -fsS --max-time 8 https://ipapi.co/country/ 2>/dev/null | tr -d '[:space:]' || true);;
          ifconfig) country=$(curl "$fam" -fsS --max-time 8 https://ifconfig.co/country-iso 2>/dev/null | tr -d '[:space:]' || true);;
        esac
        country=${country:-unavailable}; echo "$provider: $country"
        if [[ "$country" =~ ^[A-Z]{2}$ ]]; then signals=$((signals+1)); if [[ "$country" == "$TARGET" ]];then match=$((match+1));else mismatch=$((mismatch+1));fi;fi
      done
    done
    echo "--- GeoIP signal summary (not Google's internal decision) ---"
    echo "Target: $TARGET | matching provider signals: $match | conflicting/other signals: $mismatch | usable signals: $signals"
    if (( signals == 0 ));then echo "Confidence: INSUFFICIENT DATA";elif (( match == signals ));then echo "Confidence: CONSISTENT GeoIP signals";elif (( match > 0 ));then echo "Confidence: MIXED GeoIP signals";else echo "Confidence: NO GeoIP provider currently reports target";fi
    echo "--- Google Locale Matrix ---"
    local matrix_urls=("https://www.google.com/" "https://www.google.com/?hl=en" "https://www.google.com/?hl=en&gl=$TARGET" "https://www.google.com/?hl=en&gl=RU" "https://www.google.com/?hl=en&gl=US" "https://www.google.com/?hl=en&gl=DE")
    local i=0 url body headers status
    for url in "${matrix_urls[@]}"; do
      i=$((i+1));body="$TMP/matrix-body-$i";headers="$TMP/matrix-headers-$i";rm -f "$body" "$headers"
      status=$(curl -4 -sS -L -o "$body" -D "$headers" --max-time 15 -w '%{http_code}' "$url" 2>&1) || true
      echo "$url | result: $status"
      if [[ -s "$headers" ]];then grep -iE '^(HTTP/|location:|content-language:)' "$headers" | tail -4 || true;fi
      if [[ -s "$body" ]];then grep -Eo '<html[^>]*>|<title>[^<]{0,120}</title>' "$body" | head -2 || true;else echo "No response body (failed/empty)";fi
    done
    echo "--- Gemini web checks (HTTP reachability only; not account eligibility) ---"
    local gem_urls=("https://gemini.google.com/" "https://gemini.google.com/app" "https://accounts.google.com/")
    i=0
    for url in "${gem_urls[@]}";do i=$((i+1));body="$TMP/gemini-body-$i";headers="$TMP/gemini-headers-$i";rm -f "$body" "$headers";curl -4 -sS -L -o "$body" -D "$headers" --max-time 18 -w "$url | HTTP %{http_code} | IP %{remote_ip} | %{time_total}s\n" "$url" || echo "Request failed: $url";if [[ -s "$headers" ]];then grep -iE '^(HTTP/|location:|content-language:)' "$headers" | tail -5 || true;fi;if [[ -s "$body" ]];then grep -Eio 'unsupported|not available|country|region|sign in|login|error' "$body" | sort | uniq -c | head -8 || true;fi;done
    echo "--- YouTube deep HTTP checks (not playback validation) ---"
    local yt_urls=("https://www.youtube.com/" "https://www.youtube.com/?hl=en&gl=$TARGET" "https://www.youtube.com/watch?v=dQw4w9WgXcQ" "https://www.youtube.com/feed/trending")
    i=0
    for url in "${yt_urls[@]}";do i=$((i+1));body="$TMP/yt-body-$i";headers="$TMP/yt-headers-$i";rm -f "$body" "$headers";curl -4 -sS -L -o "$body" -D "$headers" --max-time 18 -w "$url | HTTP %{http_code} | IP %{remote_ip} | %{time_total}s\n" "$url" || echo "Request failed: $url";if [[ -s "$headers" ]];then grep -iE '^(HTTP/|location:|content-language:)' "$headers" | tail -5 || true;fi;if [[ -s "$body" ]];then grep -Eo '<title>[^<]{0,160}</title>|ytInitialPlayerResponse|playabilityStatus|LOGIN_REQUIRED|ERROR' "$body" | head -5 || true;fi;done
    echo "--- DNS / routes / interfaces ---"
    for host in google.com accounts.google.com gemini.google.com youtube.com googleapis.com googlevideo.com gstatic.com;do printf '%-24s ' "$host";getent ahostsv4 "$host"|awk '!seen[$1]++{print $1}'|paste -sd ','||true;done
    ip -4 route;ip -6 route 2>/dev/null||true;ip -br addr
    resolvectl status 2>/dev/null|sed -n '1,55p'||true
    echo "--- Time / locale ---";timedatectl 2>&1||true;locale 2>&1||true
    echo "--- IP registration (best effort) ---"
    if command -v whois >/dev/null 2>&1;then if [[ -n "$ipv4" ]];then whois "$ipv4" 2>&1|head -45||true;else echo "IPv4 unavailable; WHOIS skipped";fi;else echo "whois utility not installed; skipped";fi
    echo "--- Google Service Health Summary ---"
    local test_urls=("https://www.google.com/" "https://accounts.google.com/" "https://gemini.google.com/app" "https://www.youtube.com/" "https://www.googleapis.com/" "https://www.gstatic.com/")
    local health_names=("Search" "Account endpoint" "Gemini web" "YouTube web" "Google APIs root" "Google static assets")
    local h=0 hurl hcode
    for hurl in "${test_urls[@]}";do
      h=$((h+1));hcode=$(curl -4 -sS -L -o /dev/null --max-time 12 -w '%{http_code}' "$hurl" 2>/dev/null || true)
      printf '%-22s HTTP %s\n' "${health_names[$((h-1))]}" "${hcode:-FAIL}"
      case "$hcode" in
        2??|3??) echo "  Signal: endpoint responds";;
        401|403) echo "  Signal: endpoint reachable; access/auth policy may apply";;
        404) echo "  Signal: host reachable; root/path may not provide a resource";;
        5??) echo "  Signal: remote server error";;
        000|\|*) echo "  Signal: connection/TLS/DNS failure or timeout";;
        *) echo "  Signal: inconclusive";;
      esac
    done
    echo "--- Interpretation ---"
    echo "GeoIP services are external estimates; Google Locale Matrix reflects requested URL signals and response HTML only."
    echo "Gemini HTTP status cannot confirm sign-in, account eligibility, or regional availability."
    echo "YouTube HTTP/HTML checks cannot confirm video playback, Premium eligibility, or account-specific restrictions."
    echo "No network configuration is changed by this analyzer."
  }
  analyzer_core | tee "$REPORT"
  chmod 600 "$REPORT"
  rm -rf "$TMP"
  echo "Report saved (permissions 600): $REPORT"
}
showlog(){ echo '--- last 100 log lines (not re-logged) ---';tail -100 "$LOG" | sed 's/^/[LOG] /'; }
menu(){ root;while true;do header;echo '1) Full diagnostics';echo '2) Change target country/timezone';echo '3) Compare GeoIP with target';echo '4) DNS diagnostics';echo '5) Set DNS (persistent)';echo '6) IPv6 diagnostics';echo '7) Set target timezone';echo '8) Remove managed DNS override';echo '9) Show log';echo '10) Google Region Deep Analyzer';echo '0) Exit';read -r -p 'Select: ' o;case "$o" in 1)diagnostics;pause;;2)settarget;pause;;3)compare;pause;;4)dns;pause;;5)dnsset;pause;;6)ipv6;pause;;7)tzset;pause;;8)restore_dns;pause;;9)showlog;pause;;10)google_region_analyzer;pause;;0)exit;;*)echo 'Invalid option';pause;;esac;done;}
menu
