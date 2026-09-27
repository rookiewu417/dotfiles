#!/usr/bin/env bash
# Claude Code hook: show a Windows toast from WSL when Claude finishes (Stop)
# or needs input (Notification). Reads the hook JSON from stdin.

PS=/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe
[[ -x $PS ]] || exit 0 # not WSL: nothing to do

input=$(cat)

# Flatten whitespace and truncate in jq (counts characters, not bytes).
IFS=$'\x1f' read -r event cwd msg last < <(jq -r '[
    (.hook_event_name // ""),
    (.cwd // ""),
    (.message // ""),
    (.last_assistant_message // "")
  ] | map(tostring | gsub("\\s+"; " ") | if length > 120 then .[0:120] + "…" else . end)
    | join("\u001f")' <<<"$input")

project=$(basename "${cwd:-$PWD}")
case $event in
  Stop) title="Claude 已完成 · $project" body=${last:-任务完成} ;;
  Notification) title="Claude 需要你 · $project" body=${msg:-等待输入} ;;
  *) title="Claude Code · $project" body=${msg:-$event} ;;
esac

q() { printf "'%s'" "${1//\'/\'\'}"; } # PowerShell single-quoted literal

ps_script="
[Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType=WindowsRuntime] | Out-Null
[Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType=WindowsRuntime] | Out-Null
\$x = New-Object Windows.Data.Xml.Dom.XmlDocument
\$x.LoadXml('<toast><visual><binding template=\"ToastGeneric\"><text/><text/></binding></visual><audio src=\"ms-winsoundevent:Notification.Default\"/></toast>')
\$t = \$x.GetElementsByTagName('text')
\$t.Item(0).AppendChild(\$x.CreateTextNode($(q "$title"))) | Out-Null
\$t.Item(1).AppendChild(\$x.CreateTextNode($(q "$body"))) | Out-Null
\$app = '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\\WindowsPowerShell\\v1.0\\powershell.exe'
[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier(\$app).Show([Windows.UI.Notifications.ToastNotification]::new(\$x))
"

# -EncodedCommand (UTF-16LE base64) sidesteps quoting and keeps Chinese text intact.
encoded=$(printf '%s' "$ps_script" | iconv -f UTF-8 -t UTF-16LE | base64 -w0)
cd /mnt/c && "$PS" -NoProfile -NonInteractive -EncodedCommand "$encoded" >/dev/null 2>&1
