{ config, pkgs, autolith, ... }:
{
  imports = [ ./hyprland.nix ./noctalia.nix ./tmux.nix ./theme.nix ./workflow.nix ./forgejo.nix ./bridge.nix ./gaming.nix ./telemetry.nix ./agent-memory.nix ./syncthing.nix ];
  home.username = "tay";
  home.homeDirectory = "/home/taylor";
  home.stateVersion = "26.05";
  xdg.enable = true;
  programs.home-manager.enable = true;
  programs.bash.enable = true;
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
  home.sessionPath = [ "${config.home.profileDirectory}/bin" ];
  home.packages = with pkgs; [
    freetube
    (jellyfin-desktop.overrideAttrs (old: {
      # Restore WebEngine transparency after a renderer switch so mpv is visible.
      patches = (old.patches or [ ]) ++ [ (pkgs.fetchurl {
        url = "https://github.com/jellyfin/jellyfin-desktop/commit/7a14b006d408c13c495b1763209a80f049102c98.patch";
        hash = "sha256-L4ijseC2D99BhwtoLAIGYiK+Azx+NXy+RiVwuvKu5q0=";
      }) ];
    }))
    claude-code
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
