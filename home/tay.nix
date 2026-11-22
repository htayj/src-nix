{ config, lib, pkgs, autolith, ... }:
{
  imports = [ ./hyprland.nix ./noctalia.nix ./tmux.nix ./theme.nix ./workflow.nix ./forgejo.nix ./bridge.nix ./autolith.nix ./gaming.nix ./telemetry.nix ./agent-memory.nix ./syncthing.nix ./emacs.nix ./openclaw.nix ];
  home.username = "tay";
  home.homeDirectory = "/home/taylor";
  home.stateVersion = "26.05";
  xdg.enable = true;
  xdg.configFile."nyxt/config.lisp".source = ./nyxt.lisp;
  xdg.configFile."nyxt/page-keys.js".source = ./nyxt-page-keys.js;
  xdg.configFile."nyxt/karakeep.lisp".source = ./nyxt-karakeep.lisp;
  programs.home-manager.enable = true;
  programs.bash.enable = true;
  # The desktop app shares config.toml with the CLI, but its browser transports
  # require an app-owned session. Override them only for terminal launches.
  programs.bash.shellAliases.codex = builtins.concatStringsSep " " [
    "agent-session codex"
    "-c 'plugins.browser@openai-bundled.enabled=false'"
    "-c 'plugins.unified-computer-use@openai-bundled.enabled=false'"
    "-c 'plugins.codex-app-tools@openai-bundled.enabled=false'"
    "-c 'mcp_servers.node_repl.enabled=false'"
  ];
  programs.rbw = {
    enable = true;
    settings = {
      base_url = "https://vault.nogroup.group";
      email = "hardy.taylor.j@gmail.com";
      pinentry = pkgs.pinentry-qt;
      # rbw rejects 0. About 136 years is effectively manual-lock-only,
      # without using u64::MAX (which can overflow timer calculations).
      lock_timeout = 4294967295;
    };
  };
  # Keep the NixOS compatibility launcher ahead of user-managed executables.
  home.sessionPath = [
    "${config.home.profileDirectory}/bin"
    "${config.home.homeDirectory}/.local/bin"
    "${config.home.homeDirectory}/.local/share/npm/bin"
  ];
  home.sessionVariables.NPM_CONFIG_PREFIX = "${config.home.homeDirectory}/.local/share/npm";
  # Use the packaged Chromium instead of downloading a generic Linux browser.
  home.file.".agent-browser/config.json".text = builtins.toJSON {
    executablePath = lib.getExe pkgs.chromium;
  };
  home.packages = with pkgs; [
    freetube
    (jellyfin-desktop.overrideAttrs (old: {
      # Restore WebEngine transparency after a renderer switch so mpv is visible.
      patches = (old.patches or [ ]) ++ [ (pkgs.fetchurl {
        url = "https://github.com/jellyfin/jellyfin-desktop/commit/7a14b006d408c13c495b1763209a80f049102c98.patch";
        hash = "sha256-L4ijseC2D99BhwtoLAIGYiK+Azx+NXy+RiVwuvKu5q0=";
      }) ];
    }))
    # Follow the native installer's mutable symlink on every launch so its
    # background updates take effect. Supply Nix's loader and libraries without
    # modifying either the upstream binary or its installer-managed launcher.
    (pkgs.writeShellScriptBin "claude" ''
      exec agent-session ${pkgs.stdenv.cc.bintools.dynamicLinker} \
        --library-path ${lib.makeLibraryPath [ pkgs.glibc pkgs.stdenv.cc.cc.lib ]} \
        "${config.home.homeDirectory}/.local/bin/claude" "$@"
    '')
    chromium
    agent-browser
    nyxt
    (pkgs.writeShellApplication {
      name = "nyxt-karakeep";
      runtimeInputs = [ config.programs.rbw.package ];
      text = ''exec ${pkgs.python3}/bin/python3 ${./nyxt-karakeep.py} "$@"'';
    })
    # Runtimes for the Claude plugins and hooks imported from work.
    nodejs
    uv
    python3
    libnotify
    gh
    tea
    forgejo-cli
    herdr
    gitleaks
    fastfetch
    autolith.packages.${pkgs.stdenv.hostPlatform.system}.default
  ];
}
