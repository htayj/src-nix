{ lib, pkgs, ... }:
let
  mannaHyprland = pkgs.writeShellApplication {
    name = "manna-hyprland";
    runtimeInputs = [ pkgs.hyprland ];
    # Hyprland 0.56+ expects to run under its watchdog launcher.
    text = ''
      trap '${pkgs.systemd}/bin/systemctl --user stop manna-cadet-session.target' EXIT
      start-hyprland -- --config "''${XDG_CONFIG_HOME:-$HOME/.config}/hypr/hyprland.lua"
    '';
  };
  mannaSession = pkgs.runCommand "manna-cadet-wayland-session" {
    passthru.providedSessions = [ "manna-cadet" ];
  } ''
    mkdir -p $out/share/wayland-sessions
    cat > $out/share/wayland-sessions/manna-cadet.desktop <<EOF
    [Desktop Entry]
    Name=Hyprland (manna-cadet)
    Comment=Hyprland with the complete manna-cadet XKB map
    Exec=${lib.getExe mannaHyprland}
    Type=Application
    DesktopNames=Hyprland
    EOF
  '';
in
{
  imports = [ ./noctalia.nix ./theme.nix ];

  systemd.user.targets.manna-cadet-session = {
    description = "Manna-cadet Hyprland session";
    bindsTo = [ "graphical-session.target" ];
    before = [ "graphical-session.target" ];
    after = [ "graphical-session-pre.target" ];
  };
  hardware.graphics.enable = true;
  security.rtkit.enable = true;

  services.xserver.enable = true;
  services.displayManager.sddm.enable = true;
  services.displayManager.defaultSession = "manna-cadet";
  services.displayManager.sddm.settings.Users.RememberLastSession = false;
  # SDDM gives an existing Last.Session entry precedence over DefaultSession.
  # Clear that entry while preserving its remembered user and other state.
  system.activationScripts.sddmDefaultSession.text = ''
    if [ -f /var/lib/sddm/state.conf ]; then
      ${lib.getExe pkgs.crudini} --set /var/lib/sddm/state.conf Last Session ""
    fi
  '';
  services.displayManager.sessionPackages = [ mannaSession ];
  services.desktopManager.plasma6.enable = true;
  services.xserver.xkb.layout = "us";

  services.printing.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  programs.firefox.enable = true;
  programs.hyprland = {
    enable = true;
    xwayland.enable = true;
  };

}
