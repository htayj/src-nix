{ config, lib, pkgs, ... }:
let
  workspaceBindings = lib.concatMapStringsSep "\n" (workspace:
    let
      number = toString workspace;
      # Hyprland numeric workspace IDs start at 1; use a named workspace for 0.
      target = if workspace == 0 then "name:0" else number;
    in ''
      hl.bind(mainMod .. " + ${number}", hl.dsp.focus({ workspace = "${target}" }), { description = "Workspace ${number}" })
      hl.bind(mainMod .. " + SHIFT + ${number}", chooseLayout(hy3 and hy3.move_to_workspace("${target}"), hl.dsp.window.move({ workspace = "${target}" })), { description = "Send window to workspace ${number}" })
    ''
  ) (lib.range 0 9);

  mannaHyprlandConfig = pkgs.writeText "manna-cadet-hyprland.lua" ''
    -- RALT is the dedicated Mod3 window-manager modifier. LALT stays normal Alt.
    local mainMod = "MOD3"
    -- Use the plugin built against the same pinned nixpkgs Hyprland as NixOS.
    -- Plugin loading can trigger another config pass; keep a usable fallback.
    hl.plugin.load("${pkgs.hyprlandPlugins.hy3}/lib/libhy3.so")
    local hy3 = hl.plugin.hy3
    local function chooseLayout(hy3Action, standardAction)
      return function()
        local workspace = hl.get_active_workspace()
        if hy3Action and workspace and workspace.tiled_layout == "hy3" then
          hl.dispatch(hy3Action)
        else
          hl.dispatch(standardAction)
        end
      end
    end
    local function focus(direction)
      return chooseLayout(hy3 and hy3.move_focus(direction), hl.dsp.focus({ direction = direction }))
    end
    local function move(direction)
      return chooseLayout(hy3 and hy3.move_window(direction), hl.dsp.window.move({ direction = direction }))
    end
    hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })
    hl.env("NOCTALIA_CONFIG_HOME", "${config.xdg.configHome}")
    -- Portals require an active graphical session and the compositor environment.
    hl.on("hyprland.start", function()
      hl.exec_cmd("${pkgs.dbus}/bin/dbus-update-activation-environment --systemd DISPLAY WAYLAND_DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_TYPE HYPRLAND_INSTANCE_SIGNATURE && ${pkgs.systemd}/bin/systemctl --user start manna-cadet-session.target")
      hl.exec_cmd("${lib.getExe pkgs.noctalia}")
    end)

    hl.config({ general = { gaps_out = 10, layout = hy3 and "hy3" or "dwindle" }, input = {
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
    hl.bind(mainMod .. " + h", focus("left"), { description = "Focus left" })
    hl.bind(mainMod .. " + l", focus("right"), { description = "Focus right" })
    hl.bind(mainMod .. " + k", focus("up"), { description = "Focus up" })
    hl.bind(mainMod .. " + j", focus("down"), { description = "Focus down" })
    hl.bind(mainMod .. " + SHIFT + h", move("left"), { description = "Move window left" })
    hl.bind(mainMod .. " + SHIFT + j", move("down"), { description = "Move window down" })
    hl.bind(mainMod .. " + SHIFT + k", move("up"), { description = "Move window up" })
    hl.bind(mainMod .. " + SHIFT + l", move("right"), { description = "Move window right" })
    if hy3 then
      hl.bind(mainMod .. " + b", hy3.make_group("h"), { description = "Horizontal split" })
      hl.bind(mainMod .. " + v", hy3.make_group("v"), { description = "Vertical split" })
      hl.bind(mainMod .. " + w", hy3.change_group("tab"), { description = "Tabbed group" })
      hl.bind(mainMod .. " + e", hy3.change_group("untab"), { description = "Untab group" })
      hl.bind(mainMod .. " + a", hy3.change_focus("raise"), { description = "Select parent group" })
      hl.bind(mainMod .. " + SHIFT + a", hy3.change_focus("lower"), { description = "Select child" })
    end
    hl.bind(mainMod .. " + F", hl.dsp.window.fullscreen_state({ internal = 0, client = 0, action = "set" }), { description = "Restore tiled window" })
    -- Layout selection is session-local; reload restores hy3 as the default.
    if hy3 then
      hl.bind(mainMod .. " + F1", function() hl.config({ general = { layout = "hy3" } }) end, { description = "Layout: hy3" })
    end
    hl.bind(mainMod .. " + F2", function() hl.config({ general = { layout = "dwindle" } }) end, { description = "Layout: dwindle" })
    hl.bind(mainMod .. " + F3", function() hl.config({ general = { layout = "master" } }) end, { description = "Layout: master" })

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
  # Hyprland canonicalizes --config at startup. Keep this bootstrap immutable
  # and follow the settings symlink afresh on every ordinary config reload.
  xdg.configFile."hypr/hyprland.lua".text = ''
    dofile("${config.xdg.configHome}/hypr/hyprland-settings.lua")
  '';
  xdg.configFile."hypr/hyprland-settings.lua".source = mannaHyprlandConfig;
  xdg.configFile."kitty/kitty.conf".text = ''
    remember_window_size no
  '';
}
