# Noctalia snapshot from work

Read over SSH from `tay@work` on 2026-10-25. No remote files were modified.

- Reference configuration: `/home/tay/src/dotfiles/hyprland/.config/noctalia/config.toml`.
- Dotfiles HEAD: `a460bbc7f6c674aa5dab82aaf2aa4b1ff62d0788` (the live working tree was read).
- Installed shell: Noctalia 5.3.0, also supplied by this flake's locked nixpkgs.
- Bar layout, dark Ayu Green selection, and soft panel transparency came from
  `/home/tay/.local/state/noctalia/settings.toml`.
- `ayu-green.json` is the palette captured from
  `/home/tay/.local/state/noctalia/community-palettes/Ayu%20Green.json`.
- `plugins/keybind-cheatsheet/` contains the text files from
  `/home/tay/.local/state/noctalia/plugins/materialized/community/keybind-cheatsheet/`.
  Manifest: `kenn/keybind-cheatsheet` 0.3.0, author kenn, license MIT, plugin API 9.
  Its optional thumbnail was not copied. Runtime binding caches were not copied.

The adapted settings live in `modules/noctalia.nix`. The plugin is loaded from
the immutable Nix store; automatic plugin updates are disabled. Its modifier
labels and configuration path describe this host, rather than work's Lua setup.
Monitor-specific lockscreen coordinates, notification history, clipboard data,
and unrelated live-background programs were not imported.
