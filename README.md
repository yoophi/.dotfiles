# dotfiles

Personal dotfiles managed by [chezmoi](https://www.chezmoi.io/).

## Managed files

- `~/.zshrc`
- `~/.zprofile`
- `~/.zshenv`
- `~/.p10k.zsh`
- `~/.config/nvim`
- `~/.emacs.d/init.el`
- `~/.hammerspoon`

Generated package directories, caches, local history, and secret files are intentionally not tracked.

## Restore on a new Mac

```sh
brew install chezmoi
chezmoi init git@github.com:yoophi/dotfiles.git
chezmoi diff
chezmoi apply
```

If the repository redirects to `yoophi/.dotfiles`, that is expected for the current GitHub repo.

Secrets are expected to live in `~/.secrets`, which is sourced by `~/.zprofile` but not tracked here.
