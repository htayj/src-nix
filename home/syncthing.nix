{ config, ... }:
{
  # Personal Syncthing; the GUI stays on the module default 127.0.0.1:8384.
  # The bcrypt hash lives outside the repository; its password is in rbw
  # as "syncthing gui (nixos)".
  services.syncthing = {
    enable = true;
    guiCredentials = {
      username = "tay";
      passwordFile = "${config.home.homeDirectory}/.local/share/syncthing-secrets/gui-password.bcrypt";
    };
    # Mirrors with the work laptop (repos and allow-listed ~/.claude): desk-* send, work-* receive.
    settings = {
      devices = {
        nixos.id = "YKMMZMO-SWOOBYS-NFWAFPF-YCFL3S2-LG6C4HL-WF234TE-OETDKC4-Z6A3XAM";
        work.id = "FZJMDAV-K7UYTBT-5XFGCGY-GEXYNIE-KHBHSPL-LHCCECR-VLT2GWI-4NFZTAC";
      };
      folders = {
        desk-bridge = {
          path = "${config.home.homeDirectory}/projects/bridge";
          type = "sendonly";
          devices = [ "nixos" "work" ];
        };
        desk-claude-plugin-marketplace = {
          path = "${config.home.homeDirectory}/claude-plugin-marketplace";
          type = "sendonly";
          devices = [ "nixos" "work" ];
        };
        desk-claude-notes = {
          path = "${config.home.homeDirectory}/claude-notes";
          type = "sendonly";
          devices = [ "nixos" "work" ];
        };
        desk-claude = {
          path = "${config.home.homeDirectory}/.claude";
          type = "sendonly";
          devices = [ "nixos" "work" ];
        };
        work-bridge = {
          path = "${config.home.homeDirectory}/projects/work-bridge";
          type = "receiveonly";
          devices = [ "nixos" "work" ];
        };
        work-claude-plugin-marketplace = {
          path = "${config.home.homeDirectory}/work-claude-plugin-marketplace";
          type = "receiveonly";
          devices = [ "nixos" "work" ];
        };
        work-claude-notes = {
          path = "${config.home.homeDirectory}/work-claude-notes";
          type = "receiveonly";
          devices = [ "nixos" "work" ];
        };
        work-claude = {
          path = "${config.home.homeDirectory}/work-claude";
          type = "receiveonly";
          devices = [ "nixos" "work" ];
        };
      };
    };
  };
  # Skip the automatic ~/Sync folder on first start.
  systemd.user.services.syncthing.Service.Environment = [ "STNODEFAULTFOLDER=1" ];
}
