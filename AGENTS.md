# Repository work

- Re-read the current files and Git status before editing. Preserve unrelated work.
- System configuration is in `modules/` and `hosts/`; standalone Home Manager is
  in `home/`. Keep privileged services in NixOS and personal settings in Home Manager.
- `tay@work` is read-only. Do not change files or services on that host.
- Keep Bridge source in `/home/taylor/projects/bridge` and the Claude plugin
  marketplace in `/home/taylor/claude-plugin-marketplace`, outside this repo.
  Nix may declare runtimes/services referencing those paths, not vendor their code.
- Never copy private keys, passphrases, tokens, or recovery material into this
  repository or Nix expressions. Do not print those values. Nix source is not secret.
- Run `scripts/check-secrets` before any build/commit when new content is added;
  run `nix flake check path:.` and build both configurations for split-wide changes.
- Install the staged-secret hook with `scripts/setup-git-hooks`. Never bypass it.
- Sign every new commit with the agent key, using:
  `git -c user.email=htayj@users.noreply.github.com -c gpg.format=openpgp -c gpg.program=/home/taylor/.local/share/agent-signing/gpg -c user.signingkey=D0BEDCD5B63A4040FBC5BC00A6398F53FCEC1C10 commit -S`.
  The wrapper and its keyring stay outside the repository. Do not fall back to an
  unsigned commit if signing fails. Verify the resulting commit signature.
- Do not activate the system with sudo unless it is available/authorized; report
  required `rbs` steps clearly. Home activation uses `rbh` without sudo.
