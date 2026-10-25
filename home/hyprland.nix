{ config, lib, pkgs, ... }:
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
    hl.env("NOCTALIA_CONFIG_HOME", "${config.xdg.configHome}")
    -- Portals require an active graphical session and the compositor environment.
    hl.on("hyprland.start", function()
      hl.exec_cmd("${pkgs.dbus}/bin/dbus-update-activation-environment --systemd DISPLAY WAYLAND_DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_TYPE HYPRLAND_INSTANCE_SIGNATURE && ${pkgs.systemd}/bin/systemctl --user start manna-cadet-session.target")
      hl.exec_cmd("${lib.getExe pkgs.noctalia}")
    end)

    hl.config({ general = { gaps_out = 10 }, input = {
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
    hl.bind(mainMod .. " + SHIFT + h", hl.dsp.window.move({ direction = "left" }), { description = "Move window left" })
    hl.bind(mainMod .. " + SHIFT + j", hl.dsp.window.move({ direction = "down" }), { description = "Move window down" })
    hl.bind(mainMod .. " + SHIFT + k", hl.dsp.window.move({ direction = "up" }), { description = "Move window up" })
    hl.bind(mainMod .. " + SHIFT + l", hl.dsp.window.move({ direction = "right" }), { description = "Move window right" })
    hl.bind(mainMod .. " + F", hl.dsp.window.fullscreen_state({ internal = 0, client = 0, action = "set" }), { description = "Restore tiled window" })

    -- 3. Workspaces
    ${workspaceBindings}

    -- 4. Audio
    hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("${lib.getExe pkgs.noctalia} msg volume-up"), { locked = true, repeating = true, description = "Volume up" })
    hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("${lib.getExe pkgs.noctalia} msg volume-down"), { locked = true, repeating = true, description = "Volume down" })
    hl.bind("XF86AudioMute", hl.dsp.exec_cmd("${lib.getExe pkgs.noctalia} msg volume-mute"), { locked = true, repeating = true, description = "Mute audio" })
    hl.bind("XF86AudioMicMute", hl.dsp.exec_cmd("${lib.getExe pkgs.noctalia} msg mic-mute"), { locked = true, repeating = true, description = "Mute microphone" })
  '';
in
{
  home.packages = with pkgs; [ codex kdePackages.kate kitty pavucontrol rofi wl-clipboard zulip ];
  xdg.configFile."hypr/hyprland.lua".source = mannaHyprlandConfig;
  xdg.configFile."kitty/kitty.conf".text = ''
    remember_window_size no
  '';
}
