# dotfiles

个人配置文件。通过软链接安装，在仓库里改动会立即生效。

```bash
git clone https://github.com/rookiewu417/dotfiles ~/dotfiles
~/dotfiles/install.sh
```

`install.sh` 可以重复运行，结果不变；被替换的文件会先备份到 `~/.claude/backups/`。

## 内容

| 路径 | 安装到 | 说明 |
|---|---|---|
| `claude/statusline.sh` | `~/.claude/statusline.sh` | Claude Code 状态栏：模型 · effort · 目录 · 分支，以及上下文 / 5 小时 / 周额度进度条和提示词缓存倒计时。依赖 `jq`。 |
| `claude/notify.sh` | `~/.claude/notify.sh` | Claude 完成或需要你操作时弹 Windows 通知（仅 WSL，其他环境自动跳过）。 |

安装脚本还会把 `statusLine` 和 `hooks`（Stop / Notification）配置合并进 `~/.claude/settings.json`，不影响其他配置项。

## 状态栏

```
Opus 5.5 · high │ ~/proj  main
ctx █████░░░░░ 52% 104k/200k │ 5h ████████░░ 83% ↻1h42m │ 7d ████░░░░░░ 41% ↻3d04h │ cache 42m 91%
```

- **ctx**：上下文窗口占用，后面是已用 / 总量 token 数。低于 50% 灰绿，50–80% 土黄，80% 以上暗红。
- **5h / 7d**：claude.ai 订阅的 5 小时额度和周额度，`↻` 后面是距离重置的时间。低于 50% 灰蓝，50–80% 灰紫，80% 以上暗玫红。会话收到第一次回复前，或者用 API key 登录时，显示 `--`。
- **cache**：提示词缓存还剩多久过期（少于 5 分钟变黄），后面是本会话的缓存命中率。`cold` 表示缓存已过期，下一次请求会把整段上下文重新写入缓存。

状态栏在每次收到回复、`/compact`、额度重置、缓存过期时刷新，另外每 30 秒定时刷新一次。

用模拟输入测试：

```bash
echo '{"model":{"display_name":"Opus"},"context_window":{"used_percentage":25}}' | claude/statusline.sh
```

## 完成提醒

在 WSL 里通过 `powershell.exe` 弹 Windows 原生通知：

- **Stop**：Claude 回复完成时，标题「Claude 已完成 · 项目名」，内容是回复开头。
- **Notification**：需要批准权限、回答问题时，标题「Claude 需要你 · 项目名」。

钩子以 `async` 方式运行，不会拖慢 Claude Code。测试：

```bash
echo '{"hook_event_name":"Stop","cwd":"'$PWD'","last_assistant_message":"测试"}' | claude/notify.sh
```

## 许可证

MIT
