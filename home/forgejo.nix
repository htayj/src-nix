{ config, pkgs, ... }:
let
  credentialHelper = pkgs.writeShellApplication {
    name = "git-credential-forgejo";
    runtimeInputs = [ pkgs.jq ];
    text = ''
      # Git calls this helper over stdin/stdout; never log the returned token.
      [[ "''${1:-}" == get ]] || exit 0
      protocol="" host="" username=""
      while IFS='=' read -r field value; do
        [[ -n "$field" ]] || break
        case "$field" in
          protocol) protocol="$value" ;;
          host) host="$value" ;;
          username) username="$value" ;;
        esac
      done
      [[ "$protocol" == https && "$host" == forge.nogroup.group ]] || exit 0
      [[ -z "$username" || "$username" == tay ]] || exit 0
      keys="${config.xdg.dataHome}/forgejo-cli/keys.json"
      [[ -r "$keys" ]] || exit 0
      token=$(jq -er '.hosts["forge.nogroup.group"].token // empty' "$keys") || exit 0
      printf 'username=tay\npassword=%s\n\n' "$token"
    '';
  };
in
{
  home.packages = [ credentialHelper ];
}
