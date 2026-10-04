#!/usr/bin/env bash
# Ember / Field-Agent Bootstrap
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/mirarenanovark/ember-agent/main/install.sh | bash
set -euo pipefail

HERMES_DIR="$HOME/.hermes"
BIN_DIR="$HOME/.local/bin"

echo "=== Bootstrapping Ember (Hermes Field Agent) ==="

# 1. uv package manager
if ! command -v uv >/dev/null 2>&1; then
    echo "→ Installing uv..."
    curl -LsSf https://astral.sh/uv/install.sh | sh
    export PATH="$HOME/.local/bin:$PATH"
fi

# 2. Clone Hermes Agent if missing
if [ ! -d "$HERMES_DIR/hermes-agent" ]; then
    echo "→ Cloning Hermes Agent..."
    git clone --depth 1 https://github.com/nousresearch/hermes-agent.git "$HERMES_DIR/hermes-agent"
fi

cd "$HERMES_DIR/hermes-agent"
echo "→ Preparing Python 3.14 runtime..."
uv python install 3.14
uv sync

# 3. Setup CLI symlink
mkdir -p "$BIN_DIR"
ln -sf "$HERMES_DIR/hermes-agent/.venv/bin/hermes" "$BIN_DIR/hermes"
ln -sf "$HERMES_DIR/hermes-agent/.venv/bin/hermes" "$BIN_DIR/ember"
grep -q "HOME/.local/bin" ~/.bashrc || echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc

# 4. Clone / Overlay Lean Ember Identity & Skills
TEMP_DIR=$(mktemp -d)
git clone --depth 1 https://github.com/mirarenanovark/ember-agent.git "$TEMP_DIR"

mkdir -p "$HERMES_DIR/skills"
# Copy lean skills
cp -r "$TEMP_DIR/skills/." "$HERMES_DIR/skills/"
# Copy SOUL & config if not already customized
[ -f "$HERMES_DIR/SOUL.md" ] || cp "$TEMP_DIR/SOUL.md" "$HERMES_DIR/SOUL.md"
[ -f "$HERMES_DIR/config.yaml" ] || cp "$TEMP_DIR/config.yaml" "$HERMES_DIR/config.yaml"

if [ ! -f "$HERMES_DIR/.env" ]; then
    cp "$TEMP_DIR/.env.example" "$HERMES_DIR/.env"
    echo ""
    echo "⚠️  Please edit ~/.hermes/.env and insert your NINEROUTER_API_KEY!"
    echo ""
fi
rm -rf "$TEMP_DIR"

# 5. Runtime dependencies
echo "→ Installing PM dependencies..."
"$BIN_DIR/hermes" pm install

# 6. Strip out bloat skills synced by default pm install to keep start tokens minimal
for d in apple autonomous-ai-agents creative devops email media note-taking productivity research social-media web; do
    if [ -d "$HERMES_DIR/skills/$d" ]; then
        mkdir -p "$HERMES_DIR/skills-archive"
        mv "$HERMES_DIR/skills/$d" "$HERMES_DIR/skills-archive/" 2>/dev/null || true
    fi
done

echo ""
echo "=== Ember is ready! ==="
echo "Run: ember (or hermes)"
