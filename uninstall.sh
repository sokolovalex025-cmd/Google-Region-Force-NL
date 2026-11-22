#!/usr/bin/env bash
set -Eeuo pipefail
[[ $EUID -eq 0 ]] || { echo 'Run as root'; exit 1; }
systemctl disable --now google-region-force-nl-guardian.timer 2>/dev/null || true
rm -f /etc/systemd/system/google-region-force-nl-guardian.service /etc/systemd/system/google-region-force-nl-guardian.timer
rm -f /usr/local/sbin/google-region-force-nl
rm -rf /usr/local/share/google-region-force-nl
systemctl daemon-reload
echo 'Removed guardian and launcher. DNS/sysctl overrides remain; remove them from the tool menu if desired.'
