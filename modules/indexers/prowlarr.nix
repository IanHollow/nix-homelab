{ config, lib, ... }:
let
  inherit (lib)
    mkEnableOption
    mkIf
    mkOption
    types
    ;

  cfg = config.homelab.services.prowlarr;

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
        };

        systemd.services.prowlarr = {
          after = lib.mkIf cfg.vpn.enable [ "vpn-ready.service" ];
          requires = lib.mkIf cfg.vpn.enable [ "vpn-ready.service" ];
          serviceConfig = {
            DynamicUser = lib.mkForce false;
            User = lib.mkForce user;
            Group = lib.mkForce group;
            NoNewPrivileges = true;
            PrivateTmp = true;
            PrivateDevices = true;
            DevicePolicy = "closed";
            ProtectSystem = "strict";
            ProtectHome = true;
            ProtectControlGroups = true;
            ProtectKernelModules = true;
            ProtectKernelTunables = true;
            ProtectKernelLogs = true;
            ProtectClock = true;
            ProtectHostname = true;
            RestrictRealtime = true;
            RestrictSUIDSGID = true;
            RestrictNamespaces = true;
            LockPersonality = true;
            ProtectProc = "invisible";
            ProcSubset = "pid";
            CapabilityBoundingSet = "";
            AmbientCapabilities = [ ];
            RestrictAddressFamilies = [
              "AF_UNIX"
              "AF_INET"
            ]
            ++ lib.optionals config.networking.enableIPv6 [ "AF_INET6" ];
            SystemCallArchitectures = "native";
            SystemCallFilter = [ "@system-service" ];
            SystemCallErrorNumber = "EPERM";
            UMask = "0007";
            ReadWritePaths = [ config.services.prowlarr.dataDir ];
          };
        };

        systemd.tmpfiles.rules = [ "d ${config.services.prowlarr.dataDir} 0750 ${user} ${group} - -" ];
      };
    in
    mkIf cfg.enable (
      if cfg.vpn.enable then
        {
          containers.${config.homelab.vpn.container.name} = {
            bindMounts = {
              "${config.services.prowlarr.dataDir}" = bindMount config.services.prowlarr.dataDir;
            };
            config = prowlarrConfig;
          };
        }
      else
        prowlarrConfig
    );
}
