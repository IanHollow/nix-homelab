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

        systemd.services.nzbget = {
          after = lib.mkIf cfg.vpn.enable [ "vpn-ready.service" ];
          requires = lib.mkIf cfg.vpn.enable [ "vpn-ready.service" ];
          serviceConfig = {
            UMask = lib.mkForce "0007";
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
            ReadWritePaths = [
              dataDir
              storage.downloadsDir
            ];
          };
        };

        systemd.tmpfiles.rules = [ "d ${dataDir} 0750 ${user} ${group} - -" ];

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
