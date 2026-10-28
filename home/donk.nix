{ config, lib, pkgs, ... }:
let
  source = "${config.home.homeDirectory}/projects/bridge/src/donk/main.ts";
  mailbox = pkgs.writeShellApplication {
    name = "donk-messages";
    text = ''
      exec ${lib.getExe pkgs.nodejs_22} --experimental-strip-types --no-warnings ${source} "$@"
    '';
  };
in {
  # The durable mailbox and HTTPS endpoint live in Stage1, managed by Flux.
  # Clients use `donk-messages remote <identity>` and private mutable credentials.
  # No workstation daemon, OpenAI tunnel, or API key is needed here.
  home.packages = [ mailbox ];
}
