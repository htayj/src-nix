{ config, lib, pkgs, ... }:
let
  assets = ../assets/manna-cadet;
  advantage360 = "/dev/input/by-id/usb-Kinesis_Kinesis_Adv360_360555127546-if01-event-kbd";

  # Preserve distinct left/right Alt key events from Kanata. LALT is ordinary
  # application Alt/Mod1 (Emacs Meta); RALT is the dedicated compositor
  # modifier on Mod3, deliberately Super-like without being literal Super.
  runtimeKeymap = pkgs.writeTextFile {
    name = "manna-cadet-spacecadet.xkb";
    text = lib.replaceStrings
      [
        ''replace modifier_map Mod1 { <RALT> };''
        ''replace key <RALT> { type[Group1]="ONE_LEVEL", symbols[Group1]=[ Alt_L ] };''
        ''replace key <LALT> { type[Group1]="ONE_LEVEL", symbols[Group1]=[ Meta_L ] };''
        ''replace modifier_map Mod3 { <LALT>, <META> };''
      ]
      [
        ''replace modifier_map Mod1 { <LALT> };''
        ''replace key <RALT> { type[Group1]="ONE_LEVEL", symbols[Group1]=[ Meta_L ] };''
        ''replace key <LALT> { type[Group1]="ONE_LEVEL", symbols[Group1]=[ Alt_L ] };''
        ''replace modifier_map Mod3 { <RALT> };''
      ]
      (builtins.readFile (assets + "/spacecadet.xkb"));
    checkPhase = ''
      ${lib.getExe' pkgs.libxkbcommon "xkbcli"} compile-keymap \
        --from-xkb < "$target" >/dev/null
    '';
  };

  # Preserve the captured maps. The runtime-only setting makes absent USB
  # devices harmless at boot while still checking the mapping during build.
  runtimeConfig = name: source: replacements: pkgs.writeTextFile {
    name = "manna-cadet-${name}.kbd";
    text = lib.replaceStrings
      ([ "(defcfg" ] ++ replacements.from)
      ([ "(defcfg\n  linux-continue-if-no-devs-found yes" ] ++ replacements.to)
      (builtins.readFile source);
    checkPhase = ''
      ${lib.getExe config.services.kanata.package} --cfg "$target" --check --no-wait
    '';
  };
in
{
  environment.etc."nixos-manna-cadet/spacecadet.xkb".source = runtimeKeymap;

  services.kanata = {
    enable = true;
    keyboards = {
      advantage360 = {
        devices = [ advantage360 ];
        configFile = runtimeConfig "advantage360"
          (assets + "/kinesis.advantage360.layered.kanata.kbd")
          { from = [ ]; to = [ ]; };
        extraArgs = [ "--no-wait" ];
      };
      footswitches = {
        configFile = runtimeConfig "footswitches"
          (assets + "/footswitches.kanata.kbd") { from = [ ]; to = [ ]; };
        extraArgs = [ "--no-wait" ];
      };
    };
  };

  systemd.services = lib.genAttrs
    [ "kanata-advantage360" "kanata-footswitches" ]
    (_: {
      unitConfig = {
        StartLimitIntervalSec = 300;
        StartLimitBurst = 3;
      };
      serviceConfig = {
        Restart = "on-failure";
        RestartSec = 30;
      };
    });
}
