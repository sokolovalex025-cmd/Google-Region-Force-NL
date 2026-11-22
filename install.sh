#!/usr/bin/env bash
set -Eeuo pipefail
REPO="https://raw.githubusercontent.com/sokolovalex025-cmd/Google-Region-Force-NL/main"
TMP=""
cleanup(){ [[ -z "${TMP:-}" ]] || rm -rf "$TMP"; }
trap cleanup EXIT
BASE=""
if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; fi
if [[ -z "$BASE" || ! -f "$BASE/google-region-force-nl.sh" || ! -f "$BASE/guardian.sh" || ! -f "$BASE/dashboard.py" || ! -f "$BASE/systemd/google-region-force-nl-dashboard.service" || ! -f "$BASE/systemd/google-region-force-nl-guardian.timer" ]]; then
 command -v curl >/dev/null 2>&1 || { echo "curl is required." >&2; exit 1; }
 TMP="$(mktemp -d)"; BASE="$TMP/project"; mkdir -p "$BASE/systemd"
 fetch(){ local path="$1"; curl -fsSL --retry 3 --connect-timeout 10 "$REPO/$path" -o "$BASE/$path"; }
 fetch google-region-force-nl.sh
 fetch guardian.sh
 fetch dashboard.py
 fetch systemd/google-region-force-nl-dashboard.service
 fetch systemd/google-region-force-nl-guardian.service
 fetch systemd/google-region-force-nl-guardian.timer
fi
[[ $EUID -eq 0 ]] || { echo 'Run as root (or use sudo).' >&2; exit 1; }
for f in google-region-force-nl.sh guardian.sh dashboard.py systemd/google-region-force-nl-dashboard.service systemd/google-region-force-nl-guardian.service systemd/google-region-force-nl-guardian.timer; do [[ -f "$BASE/$f" ]] || { echo "Missing project file: $f"; exit 1; }; done
bash -n "$BASE/google-region-force-nl.sh"
bash -n "$BASE/guardian.sh"
python3 -m py_compile "$BASE/dashboard.py"
install -d /usr/local/sbin /etc/systemd/system /usr/local/share/google-region-force-nl
install -m 0755 "$BASE/google-region-force-nl.sh" /usr/local/share/google-region-force-nl/google-region-force-nl.sh
install -m 0755 "$BASE/guardian.sh" /usr/local/share/google-region-force-nl/guardian.sh
install -m 0755 "$BASE/dashboard.py" /usr/local/share/google-region-force-nl/dashboard.py
install -m 0644 "$BASE/systemd/google-region-force-nl-guardian.service" /etc/systemd/system/google-region-force-nl-guardian.service
install -m 0644 "$BASE/systemd/google-region-force-nl-guardian.timer" /etc/systemd/system/google-region-force-nl-guardian.timer
install -m 0644 "$BASE/systemd/google-region-force-nl-dashboard.service" /etc/systemd/system/google-region-force-nl-dashboard.service
cat > /usr/local/sbin/google-region-force-nl <<'LAUNCH'
#!/usr/bin/env bash
exec bash /usr/local/share/google-region-force-nl/google-region-force-nl.sh "$@"
LAUNCH
chmod 0755 /usr/local/sbin/google-region-force-nl
systemctl daemon-reload
systemctl enable --now google-region-force-nl-guardian.timer
systemctl enable --now google-region-force-nl-dashboard.service
echo
echo "Google Region Force NL installed."
echo "Run: google-region-force-nl"
echo "Timer: systemctl status google-region-force-nl-guardian.timer"
echo "Dashboard: localhost:8787 (SSH port forwarding)"
