{ lib, config, ... }:
let
  cfg = config.services.readarr;
in
{
  config = {
    services.readarr = {
      enable = true;
      settings.server = {
        port = 8787;
        bindaddress = "127.0.0.1";
        urlbase = "";
      };
    };

    users.groups.${cfg.group} = { };

    systemd.tmpfiles.rules = [ "d ${cfg.dataDir} 0750 ${cfg.user} ${cfg.group} - -" ];

    systemd.services.readarr.serviceConfig.UMask = lib.mkForce "0002";
  };
}
