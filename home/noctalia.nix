{ config, lib, pkgs, ... }:
let
  mediaIdleInhibit = pkgs.writeShellApplication {
    name = "media-idle-inhibit";
    runtimeInputs = [ pkgs.pipewire pkgs.jq pkgs.coreutils pkgs.wayland-pipewire-idle-inhibit ];
    text = builtins.readFile ./media-idle-inhibit.sh;
  };
  # Some DisplayPort monitors reconnect after sleeping. A one-shot DPMS request
  # then leaves the newly connected output awake until the next idle cycle.
  idleDpms = pkgs.writeShellApplication {
    name = "idle-dpms";
    runtimeInputs = [ pkgs.noctalia pkgs.coreutils ];
    text = ''
      # Noctalia stops this service on activity; standby also works unlocked.
      while true; do
        noctalia msg dpms-off
        sleep 30
      done
    '';
  };
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
      lock_before_suspend = false

      [lockscreen_widgets]
      enabled = false

      [idle]
      behavior_order = ["lock", "screen-off"]

      [idle.behavior.lock]
      action = "lock"
      enabled = false
      timeout = 300.0

      [idle.behavior.screen-off]
      # Retry while idle so a reconnected G9 returns to standby as well.
      action = "command"
      command = "${pkgs.systemd}/bin/systemctl --user start idle-dpms.service"
      resume_command = "${pkgs.systemd}/bin/systemctl --user stop idle-dpms.service; ${lib.getExe pkgs.noctalia} msg dpms-on"
      enabled = true
      timeout = 600.0
      locked_timeout = 30.0

      [bar.default]
      center = []
      start = ["clock", "launcher", "wallpaper", "workspaces"]
      end = ["media", "spacer", "cpu", "spacer", "ram", "spacer", "notifications", "clipboard", "network", "bluetooth", "volume", "brightness", "battery", "control-center", "session", "tray"]
      margin_ends = 20

      [widget.spacer]
      type = "spacer"
      length = 8

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
      hyprland_lua_config = "${config.xdg.configHome}/hypr/hyprland-settings.lua"
      modifier_labels = { MOD3 = "Thumb", ALT = "Meta", SUPER = "Super", MOD2 = "Hyper", MOD5 = "Level3" }
    '';
    checkPhase = ''
      ${lib.getExe pkgs.noctalia} config validate "$target"
    '';
  };
in
{
  home.packages = [ pkgs.noctalia ];
  # Fall back to actual audio-stream activity when a video player does not
  # supply its own Wayland/screensaver inhibitor. Exclude persistent chat audio
  # streams as well as brief notification sounds.
  systemd.user.services.media-idle-inhibit = {
    Unit = {
      Description = "Prevent display sleep during media playback";
      After = [ "pipewire.service" "pipewire-pulse.service" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = lib.getExe mediaIdleInhibit;
      Restart = "on-failure";
      RestartSec = 5;
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };
  # Started only by Noctalia's idle behavior, stopped on resumed activity.
  systemd.user.services.idle-dpms = {
    Unit = {
      Description = "Keep idle displays in DPMS standby after reconnects";
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = lib.getExe idleDpms;
      Restart = "on-failure";
      RestartSec = 5;
    };
  };
  home.sessionVariables.NOCTALIA_CONFIG_HOME = config.xdg.configHome;
  xdg.configFile."noctalia/config.toml".source = settings;
  xdg.configFile."noctalia/palettes/Ayu Green.json".source =
    ../assets/noctalia/ayu-green.json;
}
