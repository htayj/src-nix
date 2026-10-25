{ pkgs, ... }:
{
  # Set defaults without locking users out of changing their appearance.
  programs.dconf = {
    enable = true;
    profiles.user.databases = [
      {
        settings."org/gnome/desktop/interface" = {
          color-scheme = "prefer-dark";
          gtk-theme = "Adwaita-dark";
        };
      }
    ];
  };

  environment.systemPackages = [ pkgs.gnome-themes-extra ];
  environment.etc."xdg/gtk-3.0/settings.ini".text = ''
    [Settings]
    gtk-theme-name=Adwaita-dark
    gtk-application-prefer-dark-theme=true
  '';
  environment.etc."xdg/gtk-4.0/settings.ini".text = ''
    [Settings]
    gtk-application-prefer-dark-theme=true
  '';
  environment.etc."xdg/kdeglobals".text =
    builtins.readFile "${pkgs.kdePackages.breeze}/share/color-schemes/BreezeDark.colors"
    + ''

      [KDE]
      LookAndFeelPackage=org.kde.breezedark.desktop
    '';

  # Electron applications, including Zulip, read this portal for system mode.
  xdg.portal.extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
  xdg.portal.config.hyprland = {
    default = [ "hyprland" "gtk" ];
    "org.freedesktop.impl.portal.Settings" = [ "gtk" ];
  };
}
