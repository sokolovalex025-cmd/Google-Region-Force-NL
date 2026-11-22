#!/usr/bin/env bash
set -Eeuo pipefail
REPO="https://raw.githubusercontent.com/sokolovalex025-cmd/Google-Region-Force-NL/main"
TMP="$(mktemp -d)";trap 'rm -rf "$TMP"' EXIT
curl -fsSL --retry 3 "$REPO/google-region-force.sh" -o "$TMP/google-region-force.sh"
bash -n "$TMP/google-region-force.sh"
[[ $EUID -eq 0 ]]||{ echo "Run as root";exit 1;}
install -d /usr/local/share/google-region-force /usr/local/sbin
install -m 0755 "$TMP/google-region-force.sh" /usr/local/share/google-region-force/google-region-force.sh
cat > /usr/local/sbin/google-region-force <<'LAUNCH'
#!/usr/bin/env bash
exec bash /usr/local/share/google-region-force/google-region-force.sh "$@"
LAUNCH
chmod 0755 /usr/local/sbin/google-region-force
echo "Installed universal Google Region Force PRO."
echo "Run: google-region-force"
