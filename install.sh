#!/bin/bash
# orgo installer: Claude Code on OpenRouter with a per-task model picker.
# macOS only. Safe to re-run. Usage:
#   curl -fsSL https://raw.githubusercontent.com/aidan-edwards/orgo/main/install.sh | bash
set -e

REPO_RAW="https://raw.githubusercontent.com/aidan-edwards/orgo/main"
ORGO_DIR="$HOME/.orgo"
ask() { printf "%s" "$1" > /dev/tty; read -r REPLY < /dev/tty; }

echo ""
echo "🟢 orgo: Claude Code on OpenRouter, with a model picked for each task"
echo ""

[ "$(uname)" = "Darwin" ] || { echo "❌ orgo currently supports macOS only."; exit 1; }
if ! command -v claude >/dev/null 2>&1; then
  echo "⚠️  Claude Code isn't installed yet. Install it from https://claude.com/claude-code before using orgo."
fi

# 1. Command name
ask "1/4 What word should start a session? [orgo]: "; NAME="${REPLY:-orgo}"
echo "$NAME" | grep -Eq '^[a-z][a-z0-9-]{1,20}$' || { echo "❌ Use lowercase letters, numbers or hyphens."; exit 1; }

# 2. Workspace folder
ask "2/4 Folder for your projects [~/orgo-workspace]: "; WS="${REPLY:-$HOME/orgo-workspace}"
WS="${WS/#\~/$HOME}"
echo "$WS" | grep -q '["\\]' && { echo "❌ Folder path can't contain quotes or backslashes."; exit 1; }
mkdir -p "$WS"

# 3. OpenRouter key (stored in macOS Keychain, never in a file)
printf "3/4 Paste your OpenRouter API key (input hidden, get one at openrouter.ai/settings/keys): " > /dev/tty
read -rs KEY < /dev/tty; echo "" > /dev/tty
echo "$KEY" | grep -q '^sk-or-' || { echo "❌ That doesn't look like an OpenRouter key (should start with sk-or-)."; exit 1; }
CODE=$(curl -s -o /dev/null -w "%{http_code}" https://openrouter.ai/api/v1/key -H "Authorization: Bearer $KEY" || true)
[ "$CODE" = "200" ] || { echo "❌ OpenRouter rejected that key (code $CODE)."; exit 1; }
security add-generic-password -a "$USER" -s orgo-openrouter-key -w "$KEY" -U
unset KEY
echo "   ✅ Key checked and saved to your Keychain"

# 4. Sandbox
ask "4/4 Sandbox sessions to the project folder (recommended, no password needed)? [Y/n]: "
SANDBOX=yes; case "$REPLY" in n|N|no|NO) SANDBOX=no ;; esac

# Download the parts
mkdir -p "$ORGO_DIR"
curl -fsSL "$REPO_RAW/dispatch.zsh" -o "$ORGO_DIR/dispatch.zsh"
curl -fsSL "$REPO_RAW/models.js" -o "$ORGO_DIR/models.js"

cat > "$ORGO_DIR/config" <<EOF
ORGO_WORKSPACE="$WS"
# Optional overrides:
# ORGO_PLANNER_MODEL="xiaomi/mimo-v2.6-pro"
# ORGO_FALLBACK_MODEL="xiaomi/mimo-v2.6-pro"
# ORGO_EXTRA_ARGS="--chrome"
EOF

STATUS='"statusLine": { "type": "command", "command": "echo \"🟢 OPENROUTER · $ANTHROPIC_MODEL · task ${ORGO_TASK:-1/1} · max effort\"" }'
if [ "$SANDBOX" = yes ]; then
cat > "$ORGO_DIR/session-settings.json" <<EOF
{
  $STATUS,
  "permissions": {
    "blockReadsOutsideWorkingDirectories": true,
    "disableBypassPermissionsMode": "disable",
    "allow": ["WebFetch(domain:*)"]
  },
  "sandbox": {
    "enabled": true,
    "failIfUnavailable": true,
    "allowUnsandboxedCommands": false,
    "filesystem": {
      "denyRead": ["~/"],
      "allowRead": ["$WS", "~/.gitconfig", "~/.npm", "~/.npmrc", "~/.nvm", "~/.cache", "~/.local", "~/.bun", "~/.cargo", "~/.rustup", "~/.pnpm-store", "~/Library/pnpm", "~/Library/Caches"],
      "allowWrite": ["~/.npm", "~/.cache", "~/.bun", "~/.cargo", "~/.pnpm-store", "~/Library/pnpm", "~/Library/Caches"]
    }
  }
}
EOF
else
  printf '{ %s }\n' "$STATUS" > "$ORGO_DIR/session-settings.json"
fi

# Shell command
touch "$HOME/.zshrc"
sed -i.orgo-bak '/# >>> orgo >>>/,/# <<< orgo <<</d' "$HOME/.zshrc"
cat >> "$HOME/.zshrc" <<EOF
# >>> orgo >>>
unalias $NAME 2>/dev/null
function $NAME {
  local ws="$WS"
  if [ \$# -gt 0 ] && [ ! -d "\$ws/\$1" ] && whence -p $NAME >/dev/null; then command $NAME "\$@"; return; fi
  zsh "\$HOME/.orgo/dispatch.zsh" "\$@"
}
# <<< orgo <<<
EOF
zsh -n "$HOME/.zshrc" && zsh -n "$ORGO_DIR/dispatch.zsh"

echo ""
echo "✅ Installed. Open a NEW Terminal window, put a project in $WS, then type: $NAME"
echo "   Or jump straight in: $NAME <project-folder>"
