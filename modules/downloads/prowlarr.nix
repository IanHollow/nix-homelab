{ config, lib, ... }:
let
  cfg = config.services.prowlarr;

  user = "prowlarr";
  group = "prowlarr";
in
{
  config = {
    services.prowlarr = {
      enable = true;
      settings.server = {
        port = 9696;
        bindaddress = "127.0.0.1";
        urlbase = "";
      };
    };

    users.groups.${group} = { };
    users.users.${user} = {
      isSystemUser = true;
      inherit group;
    };

    systemd.tmpfiles.rules = [ "d ${cfg.dataDir} 0750 ${user} ${group} - -" ];

    systemd.services.prowlarr.serviceConfig = {
      DynamicUser = lib.mkForce false;
      User = lib.mkForce user;
      Group = lib.mkForce group;
    };
  };
}
