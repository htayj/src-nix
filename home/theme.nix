{ config, pkgs, ... }:
{
  # KDE writes GTK2 settings here. Leave that file intact during home switches.
  home.file."${config.home.homeDirectory}/.gtkrc-2.0".enable = false;
  dconf.settings."org/gnome/desktop/interface" = {
    color-scheme = "prefer-dark";
    gtk-theme = "Adwaita-dark";
  };
  gtk = {
    enable = true;
    theme = { name = "Adwaita-dark"; package = pkgs.gnome-themes-extra; };
    gtk3.extraConfig.gtk-application-prefer-dark-theme = true;
    gtk4.extraConfig.gtk-application-prefer-dark-theme = true;
  };
}
