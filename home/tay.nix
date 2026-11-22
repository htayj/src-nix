{ config, lib, pkgs, autolith, nix-channel, ... }:
{
  imports = [ ./hyprland.nix ./noctalia.nix ./tmux.nix ./theme.nix ./workflow.nix ./forgejo.nix ./bridge.nix ./autolith.nix ./gaming.nix ./telemetry.nix ./agent-memory.nix ./syncthing.nix ./emacs.nix ./openclaw.nix ];
  home.username = "tay";
  home.homeDirectory = "/home/taylor";
  home.stateVersion = "26.05";
  xdg.enable = true;
  xdg.configFile."nyxt/config.lisp".source = ./nyxt.lisp;
  xdg.configFile."nyxt/page-keys.js".source = ./nyxt-page-keys.js;
  xdg.configFile."nyxt/karakeep.lisp".source = ./nyxt-karakeep.lisp;
  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      "x-scheme-handler/codex" = [ "chatgpt.desktop" ];
      "x-scheme-handler/claude-cli" = [ "claude-code-url-handler.desktop" ];
      "text/html" = [ "firefox.desktop" ];
      "application/xhtml+xml" = [ "firefox.desktop" ];
      "x-scheme-handler/http" = [ "firefox.desktop" ];
      "x-scheme-handler/https" = [ "firefox.desktop" ];
    };
  };
  home.sessionVariables.BROWSER = "firefox";
  xdg.configFile."Element/config.json".text = builtins.toJSON {
    default_server_config."m.homeserver" = {
      base_url = "https://matrix.vexillomancy.org";
      server_name = "vexillomancy.org";
    };
  };
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
  programs.bash.shellAliases.lispterm-test = "/home/taylor/lispterm-test/bin/lispterm";
  # Share GnuPG's keyring and graphical passphrase prompt with Kleopatra and Thunderbird.
  home.file.".gnupg/gpg-agent.conf".text = ''
    pinentry-program ${lib.getExe pkgs.pinentry-qt}
  '';
  programs.rbw = {
    enable = true;
    package = nix-channel.packages.${pkgs.stdenv.hostPlatform.system}.rbw-vaultwarden;
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
  fonts.fontconfig.enable = true;
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
    thunderbird
    (pkgs.symlinkJoin {
      name = "element-desktop-with-kwallet";
      paths = [ pkgs.element-desktop ];
      nativeBuildInputs = [ pkgs.makeWrapper ];
      postBuild = ''
        wrapProgram "$out/bin/element-desktop" --add-flags "--password-store=kwallet6"
      '';
    })
    # Keep the restored Signal profile on its KWallet6 encryption backend.
    (pkgs.symlinkJoin {
      name = "signal-desktop-with-kwallet";
      paths = [ pkgs.signal-desktop ];
      nativeBuildInputs = [ pkgs.makeWrapper ];
      postBuild = ''
        wrapProgram "$out/bin/signal-desktop" --add-flags "--password-store=kwallet6"
      '';
    })
    kdePackages.kleopatra
    nyxt
    (pkgs.writeShellApplication {
      name = "nyxt-karakeep";
      runtimeInputs = [ config.programs.rbw.package ];
      text = ''exec ${pkgs.python3}/bin/python3 ${./nyxt-karakeep.py} "$@"'';
    })
    chatgpt
    gossip
    buzz-cli
    nix-channel.packages.${pkgs.stdenv.hostPlatform.system}.buzz-desktop
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
    htop
    glances
    fastfetch
    nix-channel.packages.${pkgs.stdenv.hostPlatform.system}.genera-fonts-latin
    nix-channel.packages.${pkgs.stdenv.hostPlatform.system}.genera-fonts-symbols
    autolith.packages.${pkgs.stdenv.hostPlatform.system}.default
  ];
}
