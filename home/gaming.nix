{ config, lib, pkgs, ... }:
let
  battleNet = pkgs.writeShellApplication {
    name = "battle-net";
    runtimeInputs = [ pkgs.umu-launcher pkgs.curl ];
    text = ''
      export WINEPREFIX="${config.home.homeDirectory}/Games/prefixes/battle-net"
      export PROTONPATH="${pkgs.proton-ge-bin.steamcompattool}"
      export GAMEID="umu-battlenet"
      export STORE="battlenet"
      export WINEDLLOVERRIDES="locationapi=d''${WINEDLLOVERRIDES:+;$WINEDLLOVERRIDES}"
      launcher="$WINEPREFIX/drive_c/Program Files (x86)/Battle.net/Battle.net Launcher.exe"
      if [[ -f "$launcher" ]]; then
        exec umu-run "$launcher" "$@"
      fi
      installer="''${XDG_CACHE_HOME:-$HOME/.cache}/battle-net/Battle.net-Setup.exe"
      mkdir -p "$(dirname "$installer")" "$WINEPREFIX"
      if [[ ! -s "$installer" ]]; then
        curl --fail --location --retry 3 \
          'https://www.battle.net/download/getInstallerForGame?os=win&version=LIVE&gameProgram=BATTLENET_APP' \
          --output "$installer.part"
        mv "$installer.part" "$installer"
      fi
      exec umu-run "$installer" "$@"
    '';
  };
in
{
  home.packages = [ battleNet pkgs.umu-launcher ];
  xdg.desktopEntries.battle-net = {
    name = "Battle.net";
    comment = "Battle.net in its own GE-Proton Wine prefix";
    exec = lib.getExe battleNet;
    terminal = false;
    categories = [ "Game" ];
  };
}
