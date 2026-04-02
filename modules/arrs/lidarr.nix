{ lib, config, ... }:
let
  cfg = config.services.lidarr;
in
{
  services.lidarr = {
    enable = true;
    settings.server = {
      port = 8686;
      bindaddress = "127.0.0.1";
      urlbase = "";
    };
  };

  users.groups.${cfg.group} = { };

  systemd.tmpfiles.rules = [ "d ${cfg.dataDir} 0750 ${cfg.user} ${cfg.group} - -" ];

  systemd.services.lidarr.serviceConfig.UMask = lib.mkForce "0002";
}
