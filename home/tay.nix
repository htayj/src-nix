{ config, pkgs, autolith, ... }:
{
  imports = [ ./hyprland.nix ./noctalia.nix ./tmux.nix ./theme.nix ./workflow.nix ./forgejo.nix ./bridge.nix ];
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
    autolith.packages.${pkgs.stdenv.hostPlatform.system}.default
  ];
}
