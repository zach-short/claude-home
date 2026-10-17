#!/usr/bin/env bash
# Cloud environment setup script. Copies this repo's portable config into the
# user-level Claude directory of the cloud VM. Run as root on Ubuntu 24.04.
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="${CLAUDE_DEST:-/root/.claude}"

if command -v apt-get >/dev/null 2>&1; then
  apt-get install -y -qq jq >/dev/null 2>&1 || true
fi

mkdir -p "$DEST/rules" "$DEST/agents" "$DEST/skills" "$DEST/hooks/personal-config"
cp "$SRC/CLAUDE.md" "$DEST/CLAUDE.md"
cp "$SRC"/rules/*.md "$DEST/rules/"
cp "$SRC"/agents/*.md "$DEST/agents/"
cp -R "$SRC/skills/." "$DEST/skills/"
cp "$SRC/hooks/no-em-dash.sh" "$DEST/hooks/"
cp "$SRC"/hooks/personal-config/*.sh "$DEST/hooks/personal-config/"
chmod +x "$DEST"/hooks/*.sh "$DEST"/hooks/personal-config/*.sh

echo "claude-home: config copied to $DEST"
