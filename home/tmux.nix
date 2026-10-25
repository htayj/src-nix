{ lib, pkgs, ... }:
let
  menus = pkgs.tmuxPlugins.mkTmuxPlugin {
    pluginName = "menus";
    version = "unstable-77a95a7";
    rtpFilePath = "menus.tmux";
    src = pkgs.fetchFromGitHub {
      owner = "jaclu";
      repo = "tmux-menus";
      rev = "77a95a7e31fe26ab9615f3f734c793fe436ec219";
      hash = "sha256-pqm2CFnaOdi9fpU85uoQoA/V3925liqwElcd/N7LAtQ=";
    };
    # The original plugin caches beside its source, which is read-only in Nix.
    postPatch = ''
      substituteInPlace scripts/helpers_minimal.sh \
        --replace-fail 'd_cache="$D_TM_BASE_PATH"/cache' \
          'd_cache="''${XDG_CACHE_HOME:-$HOME/.cache}/tmux-menus"'
      substituteInPlace scripts/utils/helpers_full.sh \
        --replace-fail 'd_custom_items="$D_TM_BASE_PATH"/custom_items' \
          'd_custom_items="''${XDG_CONFIG_HOME:-$HOME/.config}/tmux-menus/custom_items"'
    '';
  };
  plugins = [
    pkgs.tmuxPlugins.resurrect
    pkgs.tmuxPlugins.continuum
    menus
    pkgs.tmuxPlugins.tmux-fzf
  ];
in
{
  programs.tmux = {
    enable = true;
    shortcut = "a";
    keyMode = "emacs";
    terminal = "tmux-256color";
    baseIndex = 1;
    historyLimit = 100000;
    escapeTime = 0;
    aggressiveResize = true;
    sensibleOnTop = false;
    extraConfig = lib.replaceStrings
      [ "@TMUX_FZF@" ] [ "${pkgs.tmuxPlugins.tmux-fzf}" ]
      (builtins.readFile ../assets/tmux/tmux.conf) + "\n" + lib.concatMapStringsSep "\n"
        (plugin: "run-shell ${plugin.rtp}") plugins;
  };
  home.packages = [ pkgs.fzf ];
}
