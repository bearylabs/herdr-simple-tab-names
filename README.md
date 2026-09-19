# Herdr Simple Tab Names

A deliberately small Herdr plugin that names tabs after the foreground
process-group leader, matching tmux's automatic-renaming behavior, and prefixes
them with the tab's current position. Labels look like `1:fish`, `2:vim`, or
`3:lazygit`, with no gaps after tabs are closed or reordered.

## Files

```text
herdr-simple-tab-names/
├── herdr-plugin.toml
└── rename-tab.sh
```

## Requirements

- Herdr 0.9.1 or newer
- Bash
- `jq`

## Install

```bash
herdr plugin install bearylabs/herdr-simple-tab-names
```

Herdr Plugin v1 does not expose an event for foreground-process changes, so use
Herdr's built-in periodic command runner. Add this entry to the existing `[ui]`
section of `~/.config/herdr/config.toml`:

```toml
tab_bar_right = [
  { type = "command", command = "\"$HERDR_BIN_PATH\" plugin action invoke herdr-simple-tab-names.tick >/dev/null 2>&1", interval_seconds = 1, timeout_seconds = 2 },
]
```

If `tab_bar_right` already exists, append only the `{ type = "command", ... }`
item to that list. Then validate and reload the configuration:

```bash
herdr config check
herdr server reload-config
```

To uninstall the plugin:

```bash
herdr plugin uninstall herdr-simple-tab-names
```

There is no build step, settings file, or background daemon. The action
renumbers every tab in the focused workspace, reads each tab's foreground
process group, and avoids unnecessary renames. As in tmux, the process-group
leader determines the name;
for example, a command run through `sudo` is normally shown as `sudo`. The shell
name is used when no foreground process-group leader can be determined.

A manual rename is preserved while its numeric prefix continues to follow the
tab's position. For example, renaming a tab to `server` produces `2:server`.
To return that tab to automatic process naming, rename it to an empty string,
whitespace, or `-`. A plain numeric name such as `2` also resets it. The next
tick replaces the label with the current process name.
