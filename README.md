# NixOS and standalone Home Manager

This is the configuration for the current `nixos` host. It starts deliberately
boring: a thin flake, ordinary NixOS modules, one host directory, and the rolling
`nixos-unstable` branch pinned by `flake.lock`. The unusual keyboard
configuration is kept as its own module.

## Remotes and mirror

- Primary (`origin`): https://forge.nogroup.group/tay/src-nix — private.
- GitHub mirror: https://github.com/htayj/src-nix — private.

Push to Forgejo with `git push`; `master` tracks `origin/master`. Forgejo pushes
to GitHub on every commit, with an eight-hour periodic sync as a fallback.
This is a one-way Git mirror: make changes on Forgejo, not directly on GitHub.
Issues, pull requests, and settings are not mirrored.

The mirror uses a Forgejo-generated SSH key with write access only to the
GitHub `src-nix` repository (deploy key). No GitHub account token was copied to
Forgejo. This checkout's host-scoped credential helper uses the external `fj`
token for HTTPS pushes to Forgejo; no credentials are stored in remote URLs.
On another checkout, configure the helper with:

```sh
git config --local credential.https://forge.nogroup.group.helper ''
git config --local --add credential.https://forge.nogroup.group.helper '!git-credential-forgejo'
```

## Layout

```text
flake.nix                         flake entry point and pinned input
hosts/nixos/                      facts specific to this machine
modules/core.nix                  Nix, user, networking, base tools
modules/desktop.nix               Plasma plus a manna-cadet Hyprland session
modules/manna-cadet.nix           Kanata services and complete XKB keymap
home/tay.nix                     standalone home profile for tay
home/hyprland.nix                compositor settings, bindings, personal GUI apps
home/noctalia.nix                shell settings, palette, cheatsheet
home/tmux.nix                    tmux configuration and plugins from work
home/theme.nix                   personal GTK/dconf appearance
home/workflow.nix                rbh and live Hyprland reload
assets/manna-cadet/               captured maps, license, and provenance
```

The hardware UUIDs were copied from the fresh install's generated
`/etc/nixos/hardware-configuration.nix`. Verify them before using this config on
another machine.

## Daily rebuilds and the home/system split

- `rbs`: privileged NixOS switch, for hardware, boot, SDDM/Plasma, Kanata,
  XKB, audio, portals, GnuPG agent/Qt pinentry, and base tools including Git.
- `rbh`: standalone `home-manager switch --flake path:/home/taylor/src#tay`,
  without sudo, for personal packages (including Herdr and Autolith), shell,
  tmux, Kitty, Hyprland settings/bindings, Noctalia, and GTK/dconf appearance.
- Plasma's system-wide dark fallback remains in NixOS; the existing mutable
  `~/.config/kdeglobals` is deliberately not replaced.

Both configurations share the same pinned nixos-unstable input. Home Manager
tracks its master branch via a separate locked input that follows that nixpkgs.
Autolith keeps its own required Lisp/SBCL pin. Neither stateVersion is a package
version or an instruction to track releases; don't casually change either.

### One-time migration to standalone Home Manager

Activate the home profile **before** the system switch removes the old personal
packages and changes the session launcher. Existing GTK files are backed up,
not overwritten without recovery:

```sh
nix run path:/home/taylor/src#home-manager -- \
  -b before-home-manager switch --flake path:/home/taylor/src#tay
rbs
```

Open a new terminal to get the home profile on PATH (or `exec bash -l`). The
username stays `tay` and the home stays `/home/taylor`.

The old running compositor was started with an immutable store config path.
One logout/login after this migration selects the new stable
`~/.config/hypr/hyprland.lua` path. Thereafter `rbh` reloads Hyprland live, with
no logout. `reload-desktop` can also be run independently. The helper detects
an old session and leaves its live settings untouched instead of reloading the
obsolete store file. A compositor binary upgrade can still require a restart.
Other running apps may need their own reload (for tmux, source
`~/.config/tmux/tmux.conf`); home activation does not restart arbitrary apps.

Build without activating:

```sh
nix build path:.#homeConfigurations.tay.activationPackage --out-link result-home
nix build path:.#nixosConfigurations.nixos.config.system.build.toplevel --out-link result-system
nix flake check path:.
```

## Secret scanning and signed commits

Gitleaks uses its default rules plus a strict private-key-header rule.
`scripts/check-secrets` scans the working directory (including untracked files)
and all Git history, with findings redacted. A Nix check scans the source tree;
GitHub Actions scans the working tree and full fetched history on pushes/PRs.

For a fresh clone, before putting sensitive files anywhere near this tree:

```sh
scripts/setup-git-hooks
scripts/check-secrets
```

The repo-local pre-commit hook checks the staged diff and fails closed if the
scanner is missing. Setup pins its executable in `.git/gitleaks-bin`; the hook
does not invoke Nix on potentially sensitive staged content. Re-run setup after
updating nixpkgs or if garbage collection removes the scanner. CI can also use
`nix develop --command ./scripts/check-secrets`.

Scanning is defense in depth, not a guarantee: hooks can be bypassed and pattern
matching cannot recognize every secret or binary key format. Keep all private
keys, tokens, passphrases, and recovery material **outside the repository**.
In particular `path:` flakes copy source into the Nix store; `.gitignore` alone
does not make secret files safe to keep here. Never put secrets in Nix strings.

Agent commits must be signed with fingerprint
`D0BEDCD5B63A4040FBC5BC00A6398F53FCEC1C10`, using the external wrapper
`/home/taylor/.local/share/agent-signing/gpg`. Only public identifiers and the
wrapper path belong here; no private key or passphrase is managed by this flake.
The repo-local Git config enables signing on this machine. For another checkout:

```sh
git -c user.email=htayj@users.noreply.github.com \
  -c gpg.format=openpgp \
  -c gpg.program=/home/taylor/.local/share/agent-signing/gpg \
  -c user.signingkey=D0BEDCD5B63A4040FBC5BC00A6398F53FCEC1C10 commit -S
```

## One-time login rename

The fresh install created login `taylor`; this configuration declares `tay` with
the same UID 1000 and deliberately keeps `/home/taylor` as its home. Rename the
live account **before the first rebuild** so activation does not encounter two
names competing for UID 1000.

Set a root password with `sudo passwd root` if needed, log out of the graphical
session, switch to a text console, and log in as root. First install the script
at the top of the home directory (this only needs to be done once):

```sh
install -m 755 /home/taylor/src/scripts/rename-login-to-tay \
  /home/taylor/rename-login-to-tay
```

Then run the guarded, idempotent migration script; it performs the rename,
verifies the result, and switches this flake:

```sh
/home/taylor/rename-login-to-tay
```

The script refuses to proceed while `taylor` still owns running processes and
prints the safe cleanup command if needed. Its verification must show UID 1000,
groups `users`, `wheel`, and `networkmanager`, and home `/home/taylor`. Then log
in as `tay`. The account password is unchanged.

## First activation

The currently running system does not enable flakes yet, so the first command
must opt in explicitly:

```sh
cd /home/taylor/src
nix --extra-experimental-features 'nix-command flakes' \
  flake check path:. --no-build

sudo nixos-rebuild test \
  --flake path:/home/taylor/src#nixos \
  --option experimental-features 'nix-command flakes'
```

`test` activates the generation without making it the boot default. Check the
desktop, networking, audio, and keyboard services. If it is healthy:

```sh
sudo nixos-rebuild switch \
  --flake path:/home/taylor/src#nixos \
  --option experimental-features 'nix-command flakes'
```

After that first switch, `nix-command` and `flakes` are enabled system-wide, so
future commands can be shorter:

```sh
sudo nixos-rebuild switch --flake path:/home/taylor/src#nixos
nix flake update
```

Review and commit `flake.lock` whenever updating. The URL tracks
`nixos-unstable`, but the lock file makes each checkout reproducible until you
explicitly run `nix flake update`. A lock-file update changes the entire package
set; `system.stateVersion` should remain `26.05`.

## Manna-cadet keyboard

The maps were copied from `~/projects/nixos-basedbox/assets/manna-cadet` without
rewriting them. Their origin is recorded in
`assets/manna-cadet/provenance.json`.

Two Kanata services are enabled:

- `kanata-advantage360` watches the specific Kinesis Advantage360 device.
- `kanata-footswitches` matches devices named `PCsensor FootSwitch Keyboard`.

They tolerate missing/hot-plugged hardware and restart on unexpected failure.
The captured Advantage360 profile is preserved in `assets`: hold-S and hold-L
emit `LALT`, the thumb holds emit `RALT`, and hold-D and hold-K emit Control. At
build time the module makes LALT conventional application Alt/Mod1 (and thus
Emacs Meta), while RALT becomes the dedicated Mod3 compositor modifier. RALT is
therefore Super-like without being literal Super; Hyprland binds its
window-management actions to Mod3 only.
Inspect them with:

```sh
systemctl status kanata-advantage360 kanata-footswitches
journalctl -u kanata-advantage360 -u kanata-footswitches -b
```

The Kanata remapping is system-wide. The complete Space Cadet symbols file is a
whole XKB keymap, which Plasma/KWin cannot select through its normal RMLVO layout
settings. SDDM therefore also offers **Hyprland (manna-cadet)**; choose that
session to use the complete `spacecadet.xkb` map. Hyprland is the login default; Plasma
uses ordinary US XKB plus the Kanata device mappings.

## hy3 tiling

hy3 is the default layout, loaded from `pkgs.hyprlandPlugins.hy3` in the
Lua config. This keeps the plugin tied to the same nixpkgs Hyprland build as
the system; do not update it separately with hyprpm. If the plugin namespace
is unavailable during loading, the config retains dwindle and basic movement.

The manna-cadet map and Mod3 thumb modifier are unchanged, including held S/L
as application Alt. Existing workspace 0–9 and application shortcuts remain.

| Shortcut | Action |
| --- | --- |
| Thumb+hjkl | Focus left/down/up/right |
| Thumb+n / Thumb+p | Next / previous tab (wraps) |
| Thumb+Shift+hjkl | Move selected window/group |
| Thumb+b / Thumb+v | Create horizontal / vertical split |
| Thumb+w / Thumb+e | Tab / untab current group |
| Thumb+a / Thumb+Shift+a | Select parent group / child |
| Thumb+Shift+0–9 | Send selected window/group to workspace |
| Thumb+F1 / F2 / F3 | Switch to hy3 / dwindle / master |

In hy3, Thumb+h/l move between visible windows without selecting hidden tabs;
use Thumb+n/p to change tabs. Shift+hjkl window/group movement is unchanged.

Layout switches are session-local; reload restores hy3. Focus/move bindings
select the appropriate commands for the active workspace's layout.

`hyprland.lua` is a stable bootstrap that loads `hyprland-settings.lua` on every
reload, avoiding Hyprland's startup canonicalization of Home Manager symlinks.
Log out/in once after migrating to this bootstrap, then apply with `rbh`.
Do not use `reload full-reset` with loaded plugins: it can crash the compositor.
After updating nixpkgs, rebuild the system and restart Hyprland
before loading plugins built for a newer compositor.

## Noctalia shell

The Hyprland session starts Noctalia 5.3.0 from the locked nixpkgs. Its settings
are adapted from `tay@work` (read-only inspection); see
`assets/noctalia/PROVENANCE.md`. Plasma keeps its own shell.

- Thumb+Space: Noctalia launcher.
- Thumb+Comma: Noctalia settings.
- Thumb+Shift+Slash: keybinding cheatsheet, with this host's Thumb/Meta labels.
- Volume keys: Noctalia volume controls and on-screen display.
- Idle: lock after five minutes, screen off after ten minutes.

The cheatsheet uses live `hyprctl binds -j` data, not a second hand-maintained
key list. Categories and descriptions come from `hyprland-settings.lua`,
including hy3 splits/groups and F1–F3 layout switching. Each Hyprland config
reload requests a fresh snapshot. To refresh manually, run
`noctalia msg plugin kenn/keybind-cheatsheet:data all refresh`.

The bar layout, soft panels, and dark Ayu Green palette follow work's settings.
The captured palette and cheatsheet plugin are stored locally and pinned by the
configuration. Plugin auto-updates are disabled. Noctalia provides notifications
and the polkit agent in this session.

`home/noctalia.nix` generates `~/.config/noctalia/config.toml`; the Hyprland
session selects that directory with `NOCTALIA_CONFIG_HOME=/home/taylor/.config`. GUI changes
are saved separately in `~/.local/state/noctalia/settings.toml` and override the
declarative defaults. Use `rbh` to apply declarative changes. The system module
retains only the privileged Bluetooth, power, and networking integrations.

## Gitea CLI

Tea is installed in the home profile. On this machine, the default login
`nogroup` connects to `https://git.nogroup.group` as `tay`, authenticating with
the dedicated `nixos-tea-kube-https-20261025` token. Its scopes are
`write:repository` and `read:user`, allowing repository reads/pushes and login
verification but not administrative API operations. These scopes apply to all
repositories the account can access, not just `tay/kube`.
Its mutable login file lives in `~/.config/tea/config.yml` (mode 0600), outside
this repository and Nix. No API token or private key is stored here.

The legacy Gitea is used for the Kubernetes cluster; its advertised SSH port
422 refuses connections, so the Tea login has no SSH key selected and clones
over HTTPS. Git's host-scoped credential helper is `!tea login helper` for
`https://git.nogroup.group`. It reads the token from Tea's private config; Git
remote URLs contain no credentials. This runtime setup survives `rbh`.

Check authentication with `tea login status nogroup` or `tea whoami`.
`tay/kube` is cloned at `~/projects/kube`, with an HTTPS origin. The cluster's
Flux credentials and deploy keys were not changed. The newer Forgejo service
is separate and is not configured by this login.

## Forgejo CLI

`forgejo-cli` is installed in the home profile as `fj`. Its separate login for
`forge.nogroup.group` authenticates as `tay` using the dedicated
`nixos-fj-20261025` token. Scopes are `write:repository`, `write:issue`,
`read:user`, `read:organization`, and `read:notification`; server administration
is not enabled. Clone URLs default to HTTPS.

Check authentication with `fj -H forge.nogroup.group whoami`.
Credentials are stored only in `~/.local/share/forgejo-cli/keys.json` (0600,
parent directory 0700), outside Nix and this repository. This does not change
Tea's separate Gitea login or its host-specific Git credential helper.
`git-credential-forgejo` reads the same external token for Git HTTPS access,
and refuses requests for any other host or protocol. It is installed by Home
Manager; enable it only for the intended host in Git's credential settings.
It never embeds credentials in remotes or Nix-store files.

## Vaultwarden CLI

`rbw` is installed and configured by Home Manager for
`https://vault.nogroup.group`, using Qt pinentry and a five-minute unlock cache.
Only the server URL and account email are in Nix. Master passwords, tokens,
and the encrypted local vault remain outside the repository and Nix store.

Run `rbw login` locally and enter your master password in the pinentry dialog.
Use `rbw sync` to refresh, `rbw unlock` when needed, and `rbw lock` to lock
immediately. Never paste vault entries into chat, build logs, or Git.

## Claude Code and Bridge

Claude Code and plugin runtimes are installed in the home profile. Personal
settings, marketplace files, memories, notes, and all credentials stay outside
this repository and the Nix store.

`~/projects/bridge` is a working-tree snapshot from `tay@work`, including its
uncommitted source changes, with no Git metadata, credentials, node_modules,
or runtime state. The `bridge` user service runs it with pinned nixpkgs Node 22
(not the general-purpose Node version on PATH). Missing source prevents start.
It listens only on loopback: gateway/UI port 8787 and log API port 8788.
`BRIDGE_FALLBACK=0` matches work. It uses existing local provider credentials;
no credentials were copied from work. Claude's mutable settings point to
`http://127.0.0.1:8787`.

Inspect with `systemctl --user status bridge` and
`curl http://127.0.0.1:8787/api/hello`. Restart after source changes with
`systemctl --user restart bridge`. No model request is needed for the health check.
Bridge retains usage and session transcripts under `~/.bridge` by default
(up to 30 days / 4 GiB for sessions); treat that directory as private data.
The service runs with umask 0077. No new boot-time lingering is enabled.

## Autolith

Autolith is installed from the personal fork `github:htayj/autolith`, pinned in
`flake.lock`. It retains its upstream nixpkgs input because the package requires
a matching SBCL runtime and Lisp dependency set.

After `rbh`, run `autolith`. Provider authentication is configured separately,
for example with `autolith auth anthropic` or `autolith auth chatgpt`.

To update only the fork and rebuild:

```sh
nix flake update autolith --flake path:/home/taylor/src
rbh
```

To build it without switching the system:

```sh
nix build path:/home/taylor/src#autolith --out-link result-autolith
```

## What is actually worth enabling?

### Enabled now: `nix-command` and `flakes`

These still carry Nix's “experimental” label but are routine in community NixOS
configurations. The new CLI gives `nix build`, `nix shell`, `nix run`, and
`nix flake`; flakes add a standard output schema, pure evaluation by default,
and locked inputs. This repository keeps `flake.nix` thin so most code remains
plain NixOS modules.

The system registry and `NIX_PATH` both point at the running system's pinned
nixpkgs. That prevents `nix run nixpkgs#...` and legacy `<nixpkgs>` imports from
quietly using a different revision.

### Not yet: dendritic Nix / flake-parts

“Dendritic” is an organization pattern, not a Nix feature. Each file becomes a
module that can contribute related pieces across several configuration classes
(NixOS, Home Manager, nix-darwin, packages, and so on), commonly through
flake-parts. It shines when the same aspect—say SSH, a desktop, or an editor—must
span several hosts and module systems.

For this single-host configuration it adds concepts without removing much
duplication. Start with this explicit tree. Reconsider dendritic organization
when there are multiple hosts plus Home Manager or Darwin, or when a feature is
regularly split across several configuration classes. Moving later is a
structural refactor, not a system migration.

### Useful later, but not Nix experimental flags

- **Home Manager:** now enabled in standalone mode for personal configuration;
  system services remain in NixOS.
- **sops-nix or agenix:** use one before managing secrets. Never put plaintext
  secrets in a flake; the flake source is copied into the world-readable store.
- **disko:** excellent for repeatable installs and multiple machines. Adding it
  to an already installed host does not help day-to-day configuration and disk
  changes deserve separate review.
- **impermanence:** useful if you intentionally boot from a resettable root and
  maintain a precise persistence list. It is a lifestyle choice, not a default.
- **nh:** a pleasant wrapper around rebuilds with clearer output and generation
  cleanup, but learn the underlying `nixos-rebuild`/`nix` commands first.

### Leave disabled unless a project specifically requires them

Content-addressed derivations, dynamic derivations, recursive Nix, impure
derivations, and automatic UID allocation change build semantics or daemon
isolation. They are real experiments, not general “modern Nix” switches. Enable
one only for a workload that documents why it needs it, preferably per command
or on a disposable builder before making it system-wide.

References: [nix.dev on flakes](https://nix.dev/concepts/flakes),
[Nix experimental features](https://nix.dev/manual/nix/stable/development/experimental-features),
[flake-parts](https://flake.parts/), and
[Dendritic Nix](https://dendrix.denful.dev/Dendritic.html).
