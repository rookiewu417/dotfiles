# dotfiles

Personal config, installed by symlink so edits here take effect immediately.

```bash
git clone https://github.com/rookiewu417/dotfiles ~/dotfiles
~/dotfiles/install.sh
```

`install.sh` is idempotent. Anything it replaces is backed up to `~/.claude/backups/`.

## Contents

| Path | Installs to | What |
|---|---|---|
| `claude/statusline.sh` | `~/.claude/statusline.sh` | Claude Code status line: model · effort · dir · branch, then context / 5h / 7d usage bars and prompt-cache TTL. Needs `jq`. |

The installer also merges the `statusLine` block into `~/.claude/settings.json`, leaving other keys untouched.

## Status line

```
Opus 5.5 · high │ ~/proj  main
ctx █████░░░░░ 52% 104k/200k │ 5h ████████░░ 83% ↻1h42m │ 7d ████░░░░░░ 41% ↻3d04h │ cache 42m 91%
```

- **ctx**: context window used (muted green / yellow / red at 50% / 80%).
- **5h / 7d**: claude.ai subscription rate limits with time until reset (muted blue / lavender / rose). Shows `--` until the first response, or when logged in with an API key.
- **cache**: time until the prompt cache goes cold, then the session cache hit ratio. `cold` means the next request re-caches the whole context.

Test with mock input:

```bash
echo '{"model":{"display_name":"Opus"},"context_window":{"used_percentage":25}}' | claude/statusline.sh
```

## License

MIT
