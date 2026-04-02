{ config, ... }:
let
  cfg = config.services.jellyfin;
in
{
  config = {
    services.jellyfin = {
      enable = true;
    };

    users.groups.${cfg.group} = { };

    systemd.tmpfiles.rules = [ "d ${cfg.dataDir} 0750 ${cfg.user} ${cfg.group} - -" ];
  };
}
