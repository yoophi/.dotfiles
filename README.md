# dotfiles

Personal dotfiles managed by [chezmoi](https://www.chezmoi.io/).

## Managed files

- `~/.zshrc`, `~/.zprofile`, `~/.zshenv`, `~/.p10k.zsh`
- `~/.gitconfig` (template: git email comes from chezmoi data), `~/.gitignore`
- `~/.config/nvim`
- `~/.emacs.d/init.el`
- `~/.hammerspoon` — Hyper key (`hyper.lua`), input source switching, Agent Shortcuts,
  Agent Cockpit (`agent-cockpit.lua`, `overlay-style.lua`, `bin/agent-scan.py`, `bin/agent-cockpit-hooks.sh`),
  Agent Meter (`agent-meter.lua`: usage charts from a local `agentmeter web --live --port 9999` server)
- `~/.claude/CLAUDE.md`, `~/.claude/hooks/agent-cockpit.sh`
- `~/.codex/AGENTS.md`, `~/.codex/hooks/agent-cockpit-codex.sh`

### Deliberately not managed (see `.chezmoiignore`)

- `~/.claude/settings.json`, `~/.codex/hooks.json`, `~/.codex/config.toml` — contain API keys,
  hooks of other tools and per-machine settings. Only the Agent Cockpit hook entries are merged
  into them, by the script described below.
- `~/.hammerspoon/agent-cockpit.state.json` — runtime state written by Hammerspoon.
- `~/.oh-my-zsh`, package and plugin directories, caches, shell history.
- Secrets. They live in `~/.secrets`, which `~/.zprofile` sources when the file exists.
- Karabiner-Elements config (`~/.config/karabiner`). The Hammerspoon Hyper key expects Karabiner
  to emit **F18** (on the current machine: `right_control` and `right_option` → `f18`).

## Install on a new Mac

Prerequisites: Xcode Command Line Tools (`xcode-select --install`) and [Homebrew](https://brew.sh).

```sh
brew install chezmoi
chezmoi init git@github.com:yoophi/.dotfiles.git   # the old name yoophi/dotfiles redirects here
chezmoi diff                                        # review what will be written
chezmoi apply
```

`chezmoi init` asks once for the machine name and git email and stores them in
`~/.config/chezmoi/chezmoi.toml`. `chezmoi apply` then runs, in this order:

1. `.chezmoiscripts/run_once_before_00-install-shell-deps.sh` — `brew install` of the shell and
   editor toolchain (neovim, emacs, zsh, powerlevel10k, fzf, zoxide, direnv, pyenv, rbenv, mise, jq),
   the Hammerspoon cask, and Oh My Zsh if it is missing. Runs once per version of the script.
2. The managed files listed above.
3. `.chezmoiscripts/run_onchange_after_10-agent-cockpit-hooks.sh` — runs
   `~/.hammerspoon/bin/agent-cockpit-hooks.sh install`, which merges the Agent Cockpit hook entries
   into `~/.claude/settings.json` and `~/.codex/hooks.json` (creating them when absent).
   Re-runs only when the installer script itself changes.

### After the first apply

1. **Hammerspoon** — launch it once, grant Accessibility access when asked, and enable
   *Launch Hammerspoon at login*. It loads `~/.hammerspoon/init.lua`. The Agent Shortcuts panel
   toggles with `⌘⌥0`, the Agent Cockpit with `hyper+0`, the Agent Meter with `hyper+U`.
   Agent Meter reads `http://localhost:9999/api/dashboard`; when the server is down it shows the
   command to start it (`agentmeter web --live --port 9999`, from `~/project/agentmeter`).
2. **Karabiner-Elements** (not managed here) — map a key to `f18` so the Hyper key works.
3. **Codex** — the first interactive `codex` run shows *New hook - review required* for the five
   `agent-cockpit-codex.sh` hooks. Trust them. This step cannot be automated: the trust hash in
   `~/.codex/config.toml` is keyed by the hook's position inside `hooks.json`.
4. **Claude Code** — restart running sessions so they pick up the new hooks.
5. Verify:

   ```sh
   ~/.hammerspoon/bin/agent-cockpit-hooks.sh status
   ```

### Update an existing Mac

```sh
chezmoi update      # git pull + apply
```

Check `chezmoi status` first. Files marked `MM` were edited locally after the last apply and would
be overwritten; keep such edits with `chezmoi add <file>` before applying.

## Agent Cockpit hooks

`~/.hammerspoon/bin/agent-cockpit-hooks.sh` owns the Agent Cockpit entries inside
`~/.claude/settings.json` and `~/.codex/hooks.json`. It recognises its own entries by the hook
script name, removes them, appends the current definitions at the **end** of each event list (so
hooks of other tools keep their positions and Codex keeps trusting them), and writes only when the
result differs, backing up to `<file>.cockpit-backup-<timestamp>` first. Requires `jq`.

```sh
~/.hammerspoon/bin/agent-cockpit-hooks.sh status                 # what is installed
~/.hammerspoon/bin/agent-cockpit-hooks.sh install   [--dry-run]  # merge; no-op when already current
~/.hammerspoon/bin/agent-cockpit-hooks.sh uninstall [--dry-run]  # remove only the cockpit entries
```

Hook events — Claude Code: `Notification→waiting`, `Stop→done`, `UserPromptSubmit→working`,
`SessionStart→idle`, `SessionEnd→gone`. Codex: the same, plus `PermissionRequest→waiting`.
Each hook opens `hammerspoon://agent?...`; `agent-cockpit.lua` keeps the session list, the overlay
and the `hyper+1…9` jump targets. `bin/agent-scan.py` additionally lists sessions that have not
sent a hook event yet (started before the hooks were installed, or Codex hooks not trusted yet).
