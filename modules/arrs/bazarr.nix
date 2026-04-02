{ lib, config, ... }:
let
  cfg = config.services.bazarr;
in
{
  config = {
    services.bazarr = {
      enable = true;
      listenPort = 6767;
    };

    users.groups.${cfg.group} = { };

    systemd.tmpfiles.rules = [ "d ${cfg.dataDir} 0750 ${cfg.user} ${cfg.group} - -" ];

    systemd.services.bazarr.serviceConfig.UMask = lib.mkForce "0002";
  };
}
