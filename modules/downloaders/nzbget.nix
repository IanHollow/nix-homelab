{ lib, config, ... }:
let
  inherit (lib)
    mkEnableOption
    mkIf
    mkOption
    types
    ;

  cfg = config.homelab.apps.nzbget;
  inherit (config.homelab) storage;

  user = "nzbget";
  group = "nzbget";

  dataDir = "/var/lib/nzbget";

  bindMount = hostPath: {
    inherit hostPath;
    isReadOnly = false;
  };
in
{
  options.homelab.apps.nzbget = {
    enable = mkEnableOption "Nzbget homelab defaults";

    bindAddress = mkOption {
      type = types.str;
      default = if cfg.vpn.enable then config.homelab.vpn.container.bindAddress else "127.0.0.1";
    };

    controlPort = mkOption {
      type = types.port;
      default = 6789;
    };

    vpn = {
      enable = mkEnableOption "run NZBGet in homelab VPN app stack container";
    };
  };

  config =
    let
      nzbgetConfig = {
        services.nzbget = {
          enable = true;
          inherit user group;
          settings = {
            ControlIP = cfg.bindAddress;
            ControlPort = cfg.controlPort;
          };
        };

        systemd.services.nzbget.serviceConfig = {
          UMask = lib.mkForce "0007";
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
          ReadWritePaths = [
            dataDir
            storage.downloadsDir
          ];
        };

        systemd.tmpfiles.rules =
          if cfg.vpn.enable then
            [ "d ${dataDir} 0770 root ${storage.group} - -" ]
          else
            [ "d ${dataDir} 0750 ${user} ${group} - -" ];

        users.groups.${storage.group} = { };
        users.users.${user}.extraGroups = [ storage.group ];
      };
    in
    mkIf cfg.enable (
      if cfg.vpn.enable then
        {
          containers.${config.homelab.vpn.container.name} = {
            bindMounts = {
              "${dataDir}" = bindMount dataDir;
              "${storage.downloadsDir}" = bindMount storage.downloadsDir;
            };
            config = nzbgetConfig;
          };
        }
      else
        nzbgetConfig
    );
}
