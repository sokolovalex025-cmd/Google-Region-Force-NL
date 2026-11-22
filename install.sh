#!/usr/bin/env bash
set -Eeuo pipefail
[[ $EUID -eq 0 ]] || { echo 'Run as root'; exit 1; }
BASE="$(cd "$(dirname "$0")" && pwd)"
install -d /usr/local/sbin /etc/systemd/system /usr/local/share/google-region-force-nl
[[ -f "$BASE/google-region-force-nl.sh" && -f "$BASE/guardian.sh" ]] || { echo 'Project files missing; aborting.' >&2; exit 1; }
install -m 0755 "$BASE/google-region-force-nl.sh" /usr/local/share/google-region-force-nl/google-region-force-nl.sh
cat > /usr/local/sbin/google-region-force-nl <<'LAUNCH'
#!/usr/bin/env bash
exec bash /usr/local/share/google-region-force-nl/google-region-force-nl.sh "$@"
LAUNCH
chmod 755 /usr/local/sbin/google-region-force-nl
install -m 0755 "$BASE/guardian.sh" /usr/local/share/google-region-force-nl/guardian.sh
install -m 0644 "$BASE/systemd/google-region-force-nl-guardian.service" /etc/systemd/system/
install -m 0644 "$BASE/systemd/google-region-force-nl-guardian.timer" /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now google-region-force-nl-guardian.timer
echo 'Installed. Launch: google-region-force-nl'
