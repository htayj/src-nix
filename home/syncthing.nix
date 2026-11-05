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
  };
  # Skip the automatic ~/Sync folder on first start.
  systemd.user.services.syncthing.Service.Environment = [ "STNODEFAULTFOLDER=1" ];
}
