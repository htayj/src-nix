{ lib, pkgs, ... }:
let
  workspaceBindings = lib.concatMapStringsSep "\n" (workspace:
    let
      number = toString workspace;
      # Hyprland numeric workspace IDs start at 1; use a named workspace for 0.
      target = if workspace == 0 then "name:0" else number;
    in ''
      hl.bind(mainMod .. " + ${number}", hl.dsp.focus({ workspace = "${target}" }), { description = "Workspace ${number}" })
      hl.bind(mainMod .. " + SHIFT + ${number}", hl.dsp.window.move({ workspace = "${target}" }), { description = "Send window to workspace ${number}" })
    ''
  ) (lib.range 0 9);

  mannaHyprlandConfig = pkgs.writeText "manna-cadet-hyprland.lua" ''
    -- RALT is the dedicated Mod3 window-manager modifier. LALT stays normal Alt.
    local mainMod = "MOD3"
    hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })
    hl.env("NOCTALIA_CONFIG_HOME", "/etc/xdg")
    -- Portals require an active graphical session and the compositor environment.
    hl.on("hyprland.start", function()
      hl.exec_cmd("${pkgs.dbus}/bin/dbus-update-activation-environment --systemd DISPLAY WAYLAND_DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_TYPE HYPRLAND_INSTANCE_SIGNATURE && ${pkgs.systemd}/bin/systemctl --user start manna-cadet-session.target")
      hl.exec_cmd("${lib.getExe pkgs.noctalia}")
    end)

    hl.config({ input = {
      kb_file = "/etc/nixos-manna-cadet/spacecadet.xkb",
      repeat_delay = 660,
      repeat_rate = 25,
    } })

    -- 1. Applications
    hl.bind(mainMod .. " + Return", hl.dsp.exec_cmd("${lib.getExe pkgs.kitty}"), { description = "Terminal" })
    hl.bind(mainMod .. " + space", hl.dsp.exec_cmd("${lib.getExe pkgs.noctalia} msg panel-toggle launcher"), { description = "Launcher" })
    hl.bind(mainMod .. " + comma", hl.dsp.exec_cmd("${lib.getExe pkgs.noctalia} msg settings-toggle"), { description = "Noctalia settings" })
    hl.bind(mainMod .. " + SHIFT + slash", hl.dsp.exec_cmd("${lib.getExe pkgs.noctalia} msg panel-toggle kenn/keybind-cheatsheet:cheatsheet"), { description = "Keybinding cheatsheet" })

    -- 2. Windows and session
    hl.bind(mainMod .. " + C", hl.dsp.window.close(), { description = "Close window" })
    hl.bind(mainMod .. " + SHIFT + Q", hl.dsp.exit(), { description = "Log out" })
    hl.bind(mainMod .. " + h", hl.dsp.focus({ direction = "left" }), { description = "Focus left" })
    hl.bind(mainMod .. " + l", hl.dsp.focus({ direction = "right" }), { description = "Focus right" })
    hl.bind(mainMod .. " + k", hl.dsp.focus({ direction = "up" }), { description = "Focus up" })
    hl.bind(mainMod .. " + j", hl.dsp.focus({ direction = "down" }), { description = "Focus down" })
    hl.bind(mainMod .. " + F", hl.dsp.window.fullscreen_state({ internal = 0, client = 0, action = "set" }), { description = "Restore tiled window" })

    -- 3. Workspaces
    ${workspaceBindings}

    -- 4. Audio
    hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("${lib.getExe pkgs.noctalia} msg volume-up"), { locked = true, repeating = true, description = "Volume up" })
    hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("${lib.getExe pkgs.noctalia} msg volume-down"), { locked = true, repeating = true, description = "Volume down" })
    hl.bind("XF86AudioMute", hl.dsp.exec_cmd("${lib.getExe pkgs.noctalia} msg volume-mute"), { locked = true, repeating = true, description = "Mute audio" })
    hl.bind("XF86AudioMicMute", hl.dsp.exec_cmd("${lib.getExe pkgs.noctalia} msg mic-mute"), { locked = true, repeating = true, description = "Mute microphone" })
  '';
  mannaHyprland = pkgs.writeShellApplication {
    name = "manna-hyprland";
    runtimeInputs = [ pkgs.hyprland ];
    # Hyprland 0.56+ expects to run under its watchdog launcher.
    text = ''
      trap '${pkgs.systemd}/bin/systemctl --user stop manna-cadet-session.target' EXIT
      start-hyprland -- --config ${mannaHyprlandConfig}
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
  environment.etc."hypr/manna-cadet.lua".source = mannaHyprlandConfig;
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
  # Kitty remembers maximize state as well as dimensions. Under a tiling WM,
  # restoring that state makes a new terminal cover the whole workspace.
  environment.etc."xdg/kitty/kitty.conf".text = ''
    remember_window_size no
  '';
  programs.hyprland = {
    enable = true;
    xwayland.enable = true;
  };

  environment.systemPackages = with pkgs; [
    codex
    kdePackages.kate
    kitty
    pavucontrol
    rofi
    wl-clipboard
    zulip
  ];
}
