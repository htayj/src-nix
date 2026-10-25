{ nixpkgs, pkgs, ... }:
{
  # Despite the label, these are the community-standard modern CLI and flake
  # interface. More invasive experimental features are intentionally omitted.
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    auto-optimise-store = true;
  };

  # Make `nix run nixpkgs#...` and legacy NIX_PATH resolve to the exact source
  # used to build this system, rather than an independently moving registry.
  nix.registry.nixpkgs.flake = nixpkgs;
  nix.nixPath = [ "nixpkgs=${pkgs.path}" ];

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };

  networking.networkmanager.enable = true;
  i18n.defaultLocale = "en_US.UTF-8";
  console.keyMap = "us";

  users.users.tay = {
    isNormalUser = true;
    uid = 1000;
    description = "tay";
    home = "/home/taylor";
    extraGroups = [ "networkmanager" "wheel" ];
  };

  nixpkgs.config.allowUnfree = true;
  environment.shellAliases.rbs =
    "sudo nixos-rebuild switch --flake path:/home/taylor/src#nixos";

  programs.gnupg.agent = {
    enable = true;
    pinentryPackage = pkgs.pinentry-qt;
  };

  environment.systemPackages = with pkgs; [
    git
    gh
    gnupg
    pinentry-qt
    vim
    wget
    ripgrep
    jq
    nix-output-monitor
  ];
}
