{ config, pkgs, autolith, ... }:
{
  imports = [ ./hyprland.nix ./noctalia.nix ./tmux.nix ./theme.nix ./workflow.nix ];
  home.username = "tay";
  home.homeDirectory = "/home/taylor";
  home.stateVersion = "26.05";
  xdg.enable = true;
  programs.home-manager.enable = true;
  programs.bash.enable = true;
  home.sessionPath = [ "${config.home.profileDirectory}/bin" ];
  home.packages = with pkgs; [
    gh
    herdr
    gitleaks
    autolith.packages.${pkgs.stdenv.hostPlatform.system}.default
  ];
}
