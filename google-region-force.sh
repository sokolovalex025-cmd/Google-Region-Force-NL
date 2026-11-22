#!/usr/bin/env bash
set -Eeuo pipefail
VERSION="3.0"
CFG=/etc/google-region-force.conf
LOG=/var/log/google-region-force.log
BACK=/root/google-region-force-backups
DNS=/etc/systemd/resolved.conf.d/90-google-region-force.conf
IPV6=/etc/sysctl.d/99-google-region-force-ipv6.conf
mkdir -p "$BACK";touch "$LOG";exec > >(tee -a "$LOG") 2>&1
TARGET="";TZ_TARGET=""
if [[ -f "$CFG" ]];then source "$CFG";fi
TARGET="${TARGET:-NL}";TZ_TARGET="${TZ_TARGET:-Europe/Amsterdam}"
root(){ [[ $EUID -eq 0 ]]||{ echo "Run as root.";exit 1;};}
pause(){ read -r -p 'Press Enter...' _ || true; }
backup(){ local d="$BACK/$(date +%Y%m%d-%H%M%S)";mkdir -p "$d";for f in /etc/resolv.conf /etc/systemd/resolved.conf /etc/systemd/resolved.conf.d /etc/sysctl.conf /etc/sysctl.d "$CFG";do [[ -e "$f" ]]&&cp -a "$f" "$d/"||true;done;resolvectl status >"$d/resolved.txt" 2>&1||true;timedatectl >"$d/time.txt" 2>&1||true;echo "$d" >"$BACK/latest";echo "Backup $d";}
save(){ cat >"$CFG" <<EOF
TARGET="$TARGET"
TZ_TARGET="$TZ_TARGET"
EOF
chmod 600 "$CFG";}
header(){ clear 2>/dev/null||true;echo "Google Region Force PRO v$VERSION";echo "Target country: $TARGET";echo "Timezone: $TZ_TARGET";}
country(){ local fam="$1" url="$2";curl "$fam" -fsS --max-time 10 "$url" 2>/dev/null|tr -d '\n' || echo unavailable;}
geo(){ echo "IPv4 ipinfo: $(country -4 https://ipinfo.io/country)";echo "IPv4 ipapi: $(country -4 https://ipapi.co/country/)";echo "IPv4 ipinfo JSON:";curl -4 -fsS --max-time 10 https://ipinfo.io/json||true;echo;echo "IPv6 ipinfo: $(country -6 https://ipinfo.io/country)";echo "IPv6 ipapi: $(country -6 https://ipapi.co/country/)";}
compare(){ local c;for fam in -4 -6;do c=$(country "$fam" https://ipinfo.io/country);if [[ "$fam" == -4 ]];then echo "IPv4: $c (target $TARGET)";else echo "IPv6: $c (target $TARGET)";fi;done;echo "IP geolocation is only a proxy. Google may use account, device, browser, DNS and other signals.";}
dns(){ for d in google.com accounts.google.com gemini.google.com youtube.com googleapis.com gstatic.com googlevideo.com;do echo "-- $d";getent ahostsv4 "$d"|awk 'NR==1{print $1}'||true;done;resolvectl status||true;}
https(){ for u in https://www.google.com/ https://accounts.google.com/ https://gemini.google.com/ https://www.youtube.com/ https://www.googleapis.com/ https://www.gstatic.com/;do curl -4 -sS -o /dev/null -w "$u HTTP %{http_code} IP %{remote_ip} %{time_total}s\n" --max-time 12 "$u"||true;done;}
diagnostics(){ echo "=== GeoIP ===";geo;echo "=== Routing ===";ip -4 route;ip -6 route||true;echo "=== Interfaces ===";ip -br addr;echo "=== IPv6 ===";sysctl net.ipv6.conf.all.disable_ipv6 net.ipv6.conf.default.disable_ipv6||true;echo "=== DNS ===";cat /etc/resolv.conf;dns;echo "=== HTTPS ===";https;echo "=== Clock ===";timedatectl;echo "=== Locale ===";locale||true;echo "=== Managed files ===";ls -l "$DNS" "$IPV6" 2>/dev/null||true;compare;}
settarget(){ read -r -p "Target country ISO code (e.g. SE, NL, DE, FI, US): " c; c=$(echo "$c"|tr '[:lower:]' '[:upper:]');[[ "$c" =~ ^[A-Z]{2}$ ]]||{ echo invalid;return;};TARGET="$c";read -r -p "Timezone (e.g. Europe/Stockholm): " z;[[ -n "$z" ]]&&TZ_TARGET="$z";save;echo "Saved $TARGET / $TZ_TARGET";}
dnsset(){ echo '1 Cloudflare 2 Google 3 Quad9 4 OpenDNS';read -r -p 'Choice: ' n;case $n in 1) a='1.1.1.1 1.0.0.1';;2)a='8.8.8.8 8.8.4.4';;3)a='9.9.9.9 149.112.112.112';;4)a='208.67.222.222 208.67.220.220';;*)return;;esac;systemctl is-active --quiet systemd-resolved||{ echo resolved inactive;return;};backup;mkdir -p /etc/systemd/resolved.conf.d;printf '[Resolve]\nDNS=%s\nFallbackDNS=\nDNSOverTLS=no\nDNSSEC=no\n' "$a" >"$DNS";systemctl restart systemd-resolved;resolvectl status;}
ipv6(){ sysctl net.ipv6.conf.all.disable_ipv6 net.ipv6.conf.default.disable_ipv6;ip -6 addr;ip -6 route||true; }
tzset(){ if timedatectl list-timezones|grep -Fxq "$TZ_TARGET";then backup;timedatectl set-timezone "$TZ_TARGET";timedatectl;else echo "Timezone unavailable: $TZ_TARGET";fi;}
restore(){ read -r -p 'Remove managed DNS and IPv6 override files? [y/N] ' y;if [[ "$y" =~ ^[Yy]$ ]];then backup;rm -f "$DNS" "$IPV6";systemctl restart systemd-resolved||true;echo removed;fi;}
menu(){root;while true;do header;echo '1) Full diagnostics';echo '2) Change target country/timezone';echo '3) Compare GeoIP against target';echo '4) DNS diagnostics';echo '5) Set DNS (persistent)';echo '6) IPv6 diagnostics';echo '7) Set target timezone';echo '8) Backups/remove managed DNS override';echo '9) Show log';echo '0) Exit';read -r -p 'Select: ' o;case "$o" in 1)diagnostics;pause;;2)settarget;pause;;3)compare;pause;;4)dns;pause;;5)dnsset;pause;;6)ipv6;pause;;7)tzset;pause;;8)restore;pause;;9)tail -100 "$LOG";pause;;0)exit;;*)pause;;esac;done;}
menu
