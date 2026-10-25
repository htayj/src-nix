{ pkgs, ... }:
{
  programs.dconf.enable = true;
  # Keep Plasma's fallback here; do not take over the user's mutable kdeglobals.
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
