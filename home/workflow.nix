{ config, lib, pkgs, ... }:
let
  reloadDesktop = pkgs.writeShellApplication {
    name = "reload-desktop";
    runtimeInputs = [ pkgs.hyprland pkgs.jq pkgs.gnugrep ];
    text = ''
      if [[ -z "''${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
        exit 0
      fi
      config_path="${config.xdg.configHome}/hypr/hyprland.lua"
      # Do not reset a pre-migration session back to its old, immutable config.
      compositor_pid=$(hyprctl -j instances | jq -r --arg sig "$HYPRLAND_INSTANCE_SIGNATURE" \
        '.[] | select(.instance == $sig) | .pid')
      if [[ -z "$compositor_pid" ]] || ! grep -zFxq -- "$config_path" "/proc/$compositor_pid/cmdline"; then
        echo "Home config installed. This Hyprland session still uses the old launcher."
        echo "After the one-time rbs and next login, rbh will reload Hyprland live."
        exit 0
      fi
      hyprctl reload config-only
      errors=$(hyprctl configerrors)
      if [[ -n "''${errors//[[:space:]]/}" ]]; then
        printf '%s\n' "$errors" >&2
        exit 1
      fi
    '';
  };
  rebuildHome = pkgs.writeShellApplication {
    name = "rbh";
    runtimeInputs = [ config.programs.home-manager.package ];
    text = ''
      exec home-manager switch --flake path:/home/taylor/src#tay "$@"
    '';
  };
in
{
  home.packages = [ rebuildHome reloadDesktop ];
  # Every home switch refreshes the compositor, even if the config is unchanged.
  home.activation.reloadDesktop = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    run ${lib.getExe reloadDesktop}
  '';
}
