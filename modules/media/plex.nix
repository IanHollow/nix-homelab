{ config, ... }:
let
  cfg = config.services.plex;
in
{
  config = {
    services.plex = {
      enable = true;
    };

    users.groups.${cfg.group} = { };

    systemd.tmpfiles.rules = [ "d ${cfg.dataDir} 0750 ${cfg.user} ${cfg.group} - -" ];
  };
}
