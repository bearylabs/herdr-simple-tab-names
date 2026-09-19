#!/usr/bin/env bash
set -euo pipefail

herdr="${HERDR_BIN_PATH:-herdr}"
workspace_id="${HERDR_WORKSPACE_ID:-}"
focused_pane_id="${HERDR_PANE_ID:-}"
focused_tab_id="${HERDR_TAB_ID:-}"
state_dir="${HERDR_PLUGIN_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/herdr-simple-tab-names}"

[[ -n "$workspace_id" ]] || exit 0
mkdir -p "$state_dir"

strip_tab_prefix() {
  sed -E 's/^(\[[0-9]+\][[:space:]]*|[0-9]+:[[:space:]]*)//' <<<"$1"
}

is_auto_name_request() {
  local value
  value="$(strip_tab_prefix "$1")"
  [[ "$value" == "-" || "$value" =~ ^[0-9]+$ || "$value" =~ ^[[:space:]]*$ ]]
}

process_name() {
  local pid="$1"
  local name

  name="$(ps -p "$pid" -o comm= 2>/dev/null | awk 'NR == 1 { print; exit }')"
  name="${name##*/}"
  name="${name#-}"
  printf '%s' "$name"
}

tabs="$("$herdr" tab list --workspace "$workspace_id")"
panes="$("$herdr" pane list --workspace "$workspace_id")"

while IFS=$'\t' read -r number tab_id current_name; do
  pane_id="$(jq -r --arg tab_id "$tab_id" '
    [.result.panes[] | select(.tab_id == $tab_id)][0].pane_id // empty
  ' <<<"$panes")"

  # For the active tab, use the pane the user is actually focused on.
  if [[ "$tab_id" == "$focused_tab_id" && -n "$focused_pane_id" ]]; then
    pane_id="$focused_pane_id"
  fi
  [[ -n "$pane_id" ]] || continue

  if ! process_info="$("$herdr" pane process-info --pane "$pane_id")"; then
    continue
  fi
  IFS=$'\t' read -r shell_pid name < <(jq -r '
    .result.process_info
    | .foreground_process_group_id as $pgrp
    | [
        (.shell_pid | tostring),
        ([.foreground_processes[]? | select(.pid == $pgrp)][0].name // empty)
      ]
    | @tsv
  ' <<<"$process_info")
  name="${name##*/}"
  name="${name#-}"

  # Like tmux, use the shell when the foreground process-group leader cannot
  # be determined.
  if [[ -z "$name" ]]; then
    name="$(process_name "$shell_pid")"
  fi
  if [[ -z "$name" ]]; then
    name="${SHELL:-}"
    name="${name##*/}"
    name="${name#-}"
  fi

  [[ -n "$name" ]] || continue

  state_file="$state_dir/${tab_id//:/_}.json"
  custom_name=""
  last_name=""
  if [[ -f "$state_file" ]]; then
    last_name="$(jq -r '.last_name // empty' "$state_file")"
    custom_name="$(jq -r '.custom_name // empty' "$state_file")"

    # A label different from the one we last wrote was changed by the user.
    if [[ "$current_name" != "$last_name" ]]; then
      if is_auto_name_request "$current_name"; then
        custom_name=""
      else
        custom_name="$(strip_tab_prefix "$current_name")"
      fi
    fi
  elif ! is_auto_name_request "$current_name" && [[ ! "$current_name" =~ ^(\[[0-9]+\][[:space:]]*|[0-9]+:) ]]; then
    custom_name="$current_name"
  fi

  [[ -n "$custom_name" ]] && name="$custom_name"
  label="${number}:${name}"

  if [[ "$current_name" != "$label" ]]; then
    "$herdr" tab rename "$tab_id" "$label" >/dev/null
  fi

  tmp_file="$state_file.tmp.$$"
  jq -n --arg last_name "$label" --arg custom_name "$custom_name" \
    '{last_name: $last_name, custom_name: $custom_name}' >"$tmp_file"
  mv "$tmp_file" "$state_file"
done < <(jq -r '
  .result.tabs
  | to_entries[]
  | [(.key + 1), .value.tab_id, .value.label]
  | @tsv
' <<<"$tabs")
