{ lib, config, ... }:
let
  cfg = config.services.seerr;

  user = "seerr";
  group = "seerr";
in
{
  config = {
    services.seerr = {
      enable = true;
      port = 5055;
    };

    users.groups.${group} = { };
    users.users.${user} = {
      isSystemUser = true;
      inherit group;
    };

    systemd.tmpfiles.rules = [ "d ${cfg.configDir} 0750 ${user} ${group} - -" ];

    systemd.services.seerr.serviceConfig = {
      DynamicUser = lib.mkForce false;
      User = lib.mkForce user;
      Group = lib.mkForce group;
    };
  };
}
