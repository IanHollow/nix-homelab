{ lib, config, ... }:
let
  cfg = config.services.radarr;
in
{
  services.radarr = {
    enable = true;
    settings.server = {
      port = 7878;
      bindaddress = "127.0.0.1";
      urlbase = "";
    };
  };

  users.groups.${cfg.group} = { };

  systemd.tmpfiles.rules = [ "d ${cfg.dataDir} 0750 ${cfg.user} ${cfg.group} - -" ];

  systemd.services.radarr.serviceConfig.UMask = lib.mkForce "0002";
}
