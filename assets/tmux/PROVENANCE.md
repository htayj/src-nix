# tmux configuration

Copied read-only from `tay@work:~/.tmux.conf`, which resolves to
`~/src/dotfiles/home/.tmux.conf`, on 2026-10-25.
The dotfiles checkout was at `a460bbc7f6c674aa5dab82aaf2aa4b1ff62d0788`,
with no changes reported for this file. `work.tmux.conf` is the original snapshot.

`tmux.conf` is the locally adapted configuration, managed by standalone Home Manager
in `home/tmux.nix`. TPM is replaced by declarative Nix plugins. Resurrect,
Continuum, and tmux-fzf come from the locked nixpkgs; tmux-menus is pinned
to the exact clean checkout on work, `77a95a7e31fe26ab9615f3f734c793fe436ec219`.
Its cache is relocated from the immutable plugin directory to the user's cache.
Its optional custom menus directory is relocated to `$XDG_CONFIG_HOME/tmux-menus/custom_items`
(default `~/.config/tmux-menus/custom_items`).
The command palette uses the Nix store plugin path and fzf is installed.

Two broken hooks are omitted: work has neither the referenced tmux-send-later
plugin nor `~/.local/bin/tmux-pi-resurrect-post-save`. General session
save/restore remains enabled; the missing agent-specific hook is not recreated.
No saved sessions, credentials, or other runtime state were copied.

Ctrl+A is the prefix. Alt+0 through Alt+9 select tmux windows without a prefix
and are consumed by tmux rather than Emacs. The separate thumb/Mod3 workspace
bindings remain handled by Hyprland.
