{ config, lib, pkgs, ... }:
let
  settings = pkgs.writeTextFile {
    name = "noctalia-config.toml";
    text = ''
      [shell]
      telemetry_enabled = false
      setup_wizard_enabled = false
      polkit_agent = true

      [shell.panel]
      transparency_mode = "soft"

      [wallpaper]
      enabled = false

      [lockscreen]
      blurred_desktop = true

      [lockscreen_widgets]
      enabled = false

      [idle]
      behavior_order = ["lock", "screen-off"]

      [idle.behavior.lock]
      action = "lock"
      enabled = true
      timeout = 300.0

      [idle.behavior.screen-off]
      action = "screen_off"
      enabled = true
      timeout = 600.0

      [bar.default]
      center = []
      start = ["clock", "launcher", "wallpaper", "workspaces"]
      end = ["media", "notifications", "clipboard", "network", "bluetooth", "volume", "brightness", "battery", "control-center", "session", "tray"]
      margin_ends = 20

      [theme]
      mode = "dark"
      source = "custom"
      custom_palette = "Ayu Green"

      [plugins]
      auto_update = "none"
      enabled = ["kenn/keybind-cheatsheet"]

      [[plugins.source]]
      name = "work-snapshot"
      kind = "path"
      location = "${../assets/noctalia/plugins}"
      enabled = true

      [plugin_settings."kenn/keybind-cheatsheet"]
      compositor = "hyprland"
      hyprland_parser = "lua"
      hyprland_lua_config = "${config.xdg.configHome}/hypr/hyprland.lua"
      modifier_labels = { MOD3 = "Thumb", ALT = "Meta", SUPER = "Super", MOD2 = "Hyper", MOD5 = "Level3" }
    '';
    checkPhase = ''
      ${lib.getExe pkgs.noctalia} config validate "$target"
    '';
  };
in
{
  home.packages = [ pkgs.noctalia ];
  home.sessionVariables.NOCTALIA_CONFIG_HOME = config.xdg.configHome;
  xdg.configFile."noctalia/config.toml".source = settings;
  xdg.configFile."noctalia/palettes/Ayu Green.json".source =
    ../assets/noctalia/ayu-green.json;
}
