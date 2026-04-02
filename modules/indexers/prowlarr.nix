{ config, lib, ... }:
let
  inherit (lib)
    mkEnableOption
    mkIf
    mkOption
    types
    ;

  cfg = config.homelab.services.prowlarr;
  inherit (config.homelab) storage;

  user = "prowlarr";
  group = "prowlarr";

  bindMount = hostPath: {
    inherit hostPath;
    isReadOnly = false;
  };
in
{
  options.homelab.services.prowlarr = {
    enable = mkEnableOption "Prowlarr homelab defaults";

    bindAddress = mkOption {
      type = types.str;
      default = if cfg.vpn.enable then config.homelab.vpn.container.bindAddress else "127.0.0.1";
    };

    port = mkOption {
      type = types.port;
      default = 9696;
    };

    vpn.enable = mkEnableOption "run Prowlarr in homelab VPN app stack container";
  };

  config =
    let
      prowlarrConfig = {
        services.prowlarr = {
          enable = true;
          settings.server = {
            inherit (cfg) bindAddress port;
            urlbase = "";
          };
        };

        users.groups.${group} = { };
        users.users.${user} = {
          isSystemUser = true;
          inherit group;
          extraGroups = lib.mkIf config.homelab.storage.enable [ config.homelab.storage.group ];
        };

        systemd.services.prowlarr.serviceConfig = {
          DynamicUser = lib.mkForce false;
          User = lib.mkForce user;
          Group = lib.mkForce group;
          NoNewPrivileges = true;
          PrivateTmp = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          ProtectControlGroups = true;
          ProtectKernelModules = true;
          ProtectKernelTunables = true;
          RestrictRealtime = true;
          RestrictSUIDSGID = true;
          RestrictNamespaces = true;
          LockPersonality = true;
          ProtectProc = "invisible";
          ProcSubset = "pid";
          CapabilityBoundingSet = "";
          AmbientCapabilities = [ ];
          SystemCallArchitectures = "native";
          UMask = "0007";
          ReadWritePaths = [ config.services.prowlarr.dataDir ];
        };

        systemd.tmpfiles.rules =
          if cfg.vpn.enable then
            [ "d ${config.services.prowlarr.dataDir} 0770 root ${storage.group} - -" ]
          else
            [ "d ${config.services.prowlarr.dataDir} 0750 ${user} ${group} - -" ];
      };
    in
    mkIf cfg.enable (
      if cfg.vpn.enable then
        {
          containers.${config.homelab.vpn.container.name} = {
            bindMounts = {
              "${config.services.prowlarr.dataDir}" = bindMount config.services.prowlarr.dataDir;
              "${storage.downloadsDir}" = bindMount storage.downloadsDir;
            };
            config = prowlarrConfig;
          };
        }
      else
        prowlarrConfig
    );
}
