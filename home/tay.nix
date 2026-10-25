{ config, pkgs, autolith, ... }:
{
  imports = [ ./hyprland.nix ./noctalia.nix ./tmux.nix ./theme.nix ./workflow.nix ./forgejo.nix ];
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
      lock_timeout = 300;
    };
  };
  home.sessionPath = [ "${config.home.profileDirectory}/bin" ];
  home.packages = with pkgs; [
    claude-code
    gh
    tea
    forgejo-cli
    herdr
    gitleaks
    autolith.packages.${pkgs.stdenv.hostPlatform.system}.default
  ];
}
