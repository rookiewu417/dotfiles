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

# Claude Code status line
link claude/statusline.sh "$CLAUDE_DIR/statusline.sh"
merge_settings '.statusLine = {"type": "command", "command": "~/.claude/statusline.sh", "refreshInterval": 30}'

# Windows toast when Claude finishes or needs input (WSL only; no-op elsewhere).
# Drops any existing entry for notify.sh first so reruns don't duplicate it.
link claude/notify.sh "$CLAUDE_DIR/notify.sh"
merge_settings '
  def notify($matcher):
    (. // []) | map(select(any(.hooks[]?; .command == "~/.claude/notify.sh") | not))
    + [{hooks: [{type: "command", command: "~/.claude/notify.sh", async: true}]}
       + (if $matcher then {matcher: $matcher} else {} end)];
  .hooks.Stop |= notify(null)
  | .hooks.Notification |= notify("permission_prompt|agent_needs_input|elicitation_dialog|elicitation_url_dialog")'
