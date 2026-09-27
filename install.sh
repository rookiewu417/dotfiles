#!/usr/bin/env bash
# Install dotfiles: symlink managed files into place and merge required settings.
# Idempotent; anything replaced is backed up to ~/.claude/backups/.
set -euo pipefail

DOTFILES=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
CLAUDE_DIR=${CLAUDE_CONFIG_DIR:-$HOME/.claude}
BACKUP_DIR=$CLAUDE_DIR/backups
TS=$(date +%Y%m%d%H%M%S)

command -v jq >/dev/null || { echo "jq is required (sudo apt install jq)" >&2; exit 1; }
mkdir -p "$CLAUDE_DIR" "$BACKUP_DIR"

link() { # repo-relative src, absolute dst
  local src=$DOTFILES/$1 dst=$2
  if [[ -L $dst && $(readlink -f "$dst") == "$(readlink -f "$src")" ]]; then
    echo "ok       $dst"
    return
  fi
  if [[ -e $dst || -L $dst ]]; then
    mv "$dst" "$BACKUP_DIR/$(basename "$dst").bak-$TS"
    echo "backup   $dst -> $BACKUP_DIR/$(basename "$dst").bak-$TS"
  fi
  ln -s "$src" "$dst"
  echo "link     $dst -> $src"
}

merge_settings() { # jq filter merged into settings.json
  local settings=$CLAUDE_DIR/settings.json filter=$1
  [[ -f $settings ]] || echo '{}' >"$settings"
  local merged; merged=$(jq "$filter" "$settings")
  if [[ $merged == "$(jq . "$settings")" ]]; then
    echo "ok       $settings"
    return
  fi
  cp "$settings" "$BACKUP_DIR/settings.json.bak-$TS"
  printf '%s\n' "$merged" >"$settings"
  echo "update   $settings (backup: $BACKUP_DIR/settings.json.bak-$TS)"
}

register_toast_app() { # WSL: register the "Claude Code" toast sender (AUMID) under HKCU
  command -v reg.exe >/dev/null || { echo "skip     toast app (not WSL)"; return; }
  local win_dir key=HKCU\\Software\\Classes\\AppUserModelId\\ClaudeCode.Notify
  win_dir=$(cd /mnt/c && cmd.exe /c 'echo %LOCALAPPDATA%\ClaudeCode' 2>/dev/null | tr -d '\r')
  mkdir -p "$(wslpath "$win_dir")"
  # Official Claude icon is fetched, not committed (trademark); fall back to the bundled one.
  local icon; icon="$(wslpath "$win_dir")/icon.png"
  if curl -fsSL -A 'Mozilla/5.0' -o "$icon.tmp" https://claude.ai/apple-touch-icon.png \
    && file -b "$icon.tmp" | grep -q '^PNG image'; then
    mv "$icon.tmp" "$icon"
  else
    rm -f "$icon.tmp"
    cp "$DOTFILES/claude/claude-code-icon.png" "$icon"
    echo "warn     could not fetch Claude icon, using bundled fallback"
  fi
  reg.exe add "$key" /v DisplayName /t REG_SZ /d "Claude Code" /f >/dev/null
  reg.exe add "$key" /v IconUri /t REG_SZ /d "$win_dir\\icon.png" /f >/dev/null
  echo "register $key ($win_dir\\icon.png)"
}

# Claude Code status line
link claude/statusline.sh "$CLAUDE_DIR/statusline.sh"
merge_settings '.statusLine = {"type": "command", "command": "~/.claude/statusline.sh", "refreshInterval": 30}'

# Windows toast when Claude finishes or needs input (WSL only; no-op elsewhere).
# Drops any existing entry for notify.sh first so reruns don't duplicate it.
link claude/notify.sh "$CLAUDE_DIR/notify.sh"
register_toast_app
merge_settings '
  def notify($matcher):
    (. // []) | map(select(any(.hooks[]?; .command == "~/.claude/notify.sh") | not))
    + [{hooks: [{type: "command", command: "~/.claude/notify.sh", async: true}]}
       + (if $matcher then {matcher: $matcher} else {} end)];
  .hooks.Stop |= notify(null)
  | .hooks.Notification |= notify("permission_prompt|agent_needs_input|elicitation_dialog|elicitation_url_dialog")'
