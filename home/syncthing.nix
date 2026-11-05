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
    # Laptop paired manually; no folders are shared.
    settings.devices.work.id = "FZJMDAV-K7UYTBT-5XFGCGY-GEXYNIE-KHBHSPL-LHCCECR-VLT2GWI-4NFZTAC";
  };
  # Skip the automatic ~/Sync folder on first start.
  systemd.user.services.syncthing.Service.Environment = [ "STNODEFAULTFOLDER=1" ];
}
