#!/usr/bin/env bash
# Claude Code status line: model/effort/dir/branch + context, 5h/7d usage bars, prompt cache TTL.
# Reads the session JSON from stdin (see https://code.claude.com/docs/en/statusline).

input=$(cat)

# One jq call; \x1f separator keeps empty fields intact.
IFS=$'\x1f' read -r model effort fast dir ctx_pct ctx_size ctx_used \
  h5_pct h5_reset d7_pct d7_reset cache_warm cache_exp cache_hit < <(jq -r '[
    (.model.display_name // .model.id // "?"),
    (.effort.level // ""),
    (.fast_mode // false),
    (.workspace.current_dir // .cwd // ""),
    (.context_window.used_percentage // ""),
    (.context_window.context_window_size // 200000),
    (.context_window.current_usage
      | if . then (.input_tokens + .cache_creation_input_tokens + .cache_read_input_tokens) else "" end),
    (.rate_limits.five_hour.used_percentage // ""),
    (.rate_limits.five_hour.resets_at // ""),
    (.rate_limits.seven_day.used_percentage // ""),
    (.rate_limits.seven_day.resets_at // ""),
    (.prompt_cache | if . then .warm else "" end),
    (.prompt_cache.expires_at // ""),
    (.prompt_cache.hit_ratio // "")
  ] | map(tostring) | join("\u001f")' <<<"$input")

RST=$'\e[0m' DIM=$'\e[2m' BOLD=$'\e[1m'
RED=$'\e[31m' GRN=$'\e[32m' YEL=$'\e[33m' BLU=$'\e[34m' MAG=$'\e[35m' CYN=$'\e[36m'
SEP=" ${DIM}│${RST} "

color_for() { # pct [palette] -> muted 256-color; ctx = green/yellow/red, quota = blue/lavender/rose
  local p=${1%.*}
  if [[ $2 == quota ]]; then
    ((p >= 80)) && { printf '\e[38;5;132m'; return; }
    ((p >= 50)) && { printf '\e[38;5;103m'; return; }
    printf '\e[38;5;67m'; return
  fi
  ((p >= 80)) && { printf '\e[38;5;131m'; return; }
  ((p >= 50)) && { printf '\e[38;5;137m'; return; }
  printf '\e[38;5;65m'
}

BAR_EMPTY=$'\e[38;5;238m'

bar() { # pct color -> 10-cell bar, filled cells in color, empty cells dark gray
  local p=${1%.*} c=$2 w=10 filled i s=""
  ((p > 100)) && p=100
  filled=$(((p * w + 50) / 100))
  s+=$c
  for ((i = 0; i < filled; i++)); do s+="█"; done
  s+=$BAR_EMPTY
  for ((; i < w; i++)); do s+="░"; done
  printf '%s' "$s"
}

tok() { # tokens -> 104k / 1M
  local n=$1
  if ((n >= 1000000)); then
    awk -v n="$n" 'BEGIN{v=n/1000000; printf (v==int(v)?"%dM":"%.1fM"), v}'
  elif ((n >= 1000)); then
    printf '%dk' $(((n + 500) / 1000))
  else
    printf '%d' "$n"
  fi
}

until_reset() { # epoch -> 1h42m / 3d04h
  local s=$(($1 - $(date +%s)))
  ((s < 0)) && s=0
  if ((s >= 86400)); then printf '%dd%02dh' $((s / 86400)) $((s % 86400 / 3600))
  elif ((s >= 3600)); then printf '%dh%02dm' $((s / 3600)) $((s % 3600 / 60))
  else printf '%dm' $((s / 60)); fi
}

meter() { # label pct [reset_epoch] [palette]
  local label=$1 pct=$2 reset=$3 palette=$4
  if [[ -z $pct ]]; then
    printf '%s %s' "$label" "${BAR_EMPTY}░░░░░░░░░░${RST} ${DIM}--${RST}"
    return
  fi
  local c; c=$(color_for "$pct" "$palette")
  printf '%s %s %s%s%%%s' "$label" "$(bar "$pct" "$c")" "$c" "$(printf '%.0f' "$pct")" "$RST"
  [[ -n $reset ]] && printf ' %s↻%s%s' "$DIM" "$(until_reset "$reset")" "$RST"
}

# ── line 1: model · effort │ dir  branch
case $effort in
  low) ec=$DIM ;; medium) ec=$CYN ;; high) ec=$BLU ;; xhigh) ec=$MAG ;; max) ec=$BOLD$MAG ;; *) ec="" ;;
esac
line1="${BOLD}${model}${RST}"
[[ -n $effort ]] && line1+=" ${DIM}·${RST} ${ec}${effort}${RST}"
[[ $fast == true ]] && line1+=" ${YEL}⚡fast${RST}"

if [[ -n $dir ]]; then
  line1+="${SEP}${CYN}${dir/#$HOME/\~}${RST}"
  if branch=$(git -C "$dir" symbolic-ref --short -q HEAD 2>/dev/null) && [[ -n $branch ]]; then
    line1+="  ${MAG}${branch}${RST}"
  fi
fi

# ── line 2: ctx │ 5h │ 7d
ctx=$(meter ctx "$ctx_pct")
[[ -n $ctx_used ]] && ctx+=" ${DIM}$(tok "$ctx_used")/$(tok "$ctx_size")${RST}"
line2="${ctx}${SEP}$(meter 5h "$h5_pct" "$h5_reset" quota)${SEP}$(meter 7d "$d7_pct" "$d7_reset" quota)"

# prompt cache: time until the cached prefix goes cold (next request re-caches the whole context)
if [[ -n $cache_warm ]]; then
  cache="cache "
  left=$(( ${cache_exp:-0} - $(date +%s) ))
  if [[ $cache_warm == true && -n $cache_exp ]] && ((left > 0)); then
    if ((left < 300)); then cache+=$'\e[38;5;137m'; else cache+=$'\e[38;5;109m'; fi
    if ((left < 60)); then cache+="<1m"; else cache+="$(until_reset "$cache_exp")"; fi
    cache+=$RST
  else
    cache+="${BAR_EMPTY}cold${RST}"
  fi
  [[ -n $cache_hit ]] && cache+=" ${DIM}$(awk -v h="$cache_hit" 'BEGIN{printf "%.0f%%", h*100}')${RST}"
  line2+="${SEP}${cache}"
fi

printf '%s\n%s\n' "$line1" "$line2"
