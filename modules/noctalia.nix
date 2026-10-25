{ lib, ... }:
{
  # Privileged integrations stay in NixOS; the shell and its config live at home.
  xdg.sounds.enable = true;
  networking.networkmanager.enable = lib.mkDefault true;
  hardware.bluetooth.enable = lib.mkDefault true;
  services.upower.enable = lib.mkDefault true;
  services.power-profiles-daemon.enable = lib.mkDefault true;
}
