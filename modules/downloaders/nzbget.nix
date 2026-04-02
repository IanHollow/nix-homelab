{ lib, config, ... }:
let
  cfg = config.services.nzbget;

  dataDir = "/var/lib/nzbget";
in
{
  config = {
    services.nzbget = {
      enable = true;
      settings = {
        ControlIP = "127.0.0.1";
        ControlPort = 6789;
      };
    };

    users.groups.${cfg.group} = { };

    systemd.tmpfiles.rules = [ "d ${dataDir} 0750 ${cfg.user} ${cfg.group} - -" ];

    systemd.services.nzbget.serviceConfig.UMask = lib.mkForce "0002";
  };
}
