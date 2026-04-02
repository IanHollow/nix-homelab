{ config, lib, ... }:
let
  inherit (lib)
    mkEnableOption
    mkIf
    mkOption
    types
    ;

  cfg = config.homelab.apps.qbittorrent;
  inherit (config.homelab) storage;

  user = "qbittorrent";
  group = "qbittorrent";

  bindMount = hostPath: {
    inherit hostPath;
    isReadOnly = false;
  };
in
{
  options.homelab.apps.qbittorrent = {
    enable = mkEnableOption "qBittorrent homelab defaults";

    bindAddress = mkOption {
      type = types.str;
      default = if cfg.vpn.enable then config.homelab.vpn.container.bindAddress else "127.0.0.1";
    };

    webuiPort = mkOption {
      type = types.port;
      default = 8081;
    };

    torrentingPort = mkOption {
      type = types.port;
      default = 51413;
    };

    vpn = {
      enable = mkEnableOption "run qBittorrent in homelab VPN app stack container";
      allowInbound = mkOption {
        type = types.bool;
        default = false;
      };
    };
  };

  config =
    let
      qbittorrentConfig = {
        services.qbittorrent = {
          enable = true;
          inherit user group;
          inherit (cfg) webuiPort;
          inherit (cfg) torrentingPort;
          serverConfig.Preferences.WebUI = {
            Address = cfg.bindAddress;
            ReverseProxySupportEnabled = true;
          };
        };

        systemd.services.qbittorrent.serviceConfig = {
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
            config.services.qbittorrent.profileDir
            storage.downloadsDir
          ];
        };

        systemd.tmpfiles.rules =
          if cfg.vpn.enable then
            [ "d ${config.services.qbittorrent.profileDir} 0770 root ${storage.group} - -" ]
          else
            [ "d ${config.services.qbittorrent.profileDir} 0750 ${user} ${group} - -" ];

        users.groups.${storage.group} = { };
        users.users.${user}.extraGroups = [ storage.group ];
      };
    in
    mkIf cfg.enable (
      if cfg.vpn.enable then
        {
          containers.${config.homelab.vpn.container.name} = {
            bindMounts = {
              "${config.services.qbittorrent.profileDir}" = bindMount config.services.qbittorrent.profileDir;
              "${storage.downloadsDir}" = bindMount storage.downloadsDir;
            };
            config = qbittorrentConfig;
          };

          homelab.vpn.inboundPorts = lib.mkIf (cfg.vpn.enable && cfg.vpn.allowInbound) {
            tcp = [ cfg.torrentingPort ];
            udp = [ cfg.torrentingPort ];
          };
        }
      else
        qbittorrentConfig
    );
}
