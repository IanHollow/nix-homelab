{ config, lib, ... }:
let
  cfg = config.services.qbittorrent;
in
{
  config = {
    services.qbittorrent = {
      enable = true;
      webuiPort = 8081;
      torrentingPort = 51413;
      serverConfig.Preferences.WebUI = {
        Address = "127.0.0.1";
        ReverseProxySupportEnabled = true;
      };
    };

    users.groups.${cfg.group} = { };

    systemd.tmpfiles.rules = [ "d ${cfg.profileDir} 0750 ${cfg.user} ${cfg.group} - -" ];

    systemd.services.qbittorrent.serviceConfig.UMask = lib.mkForce "0002";
  };
}
