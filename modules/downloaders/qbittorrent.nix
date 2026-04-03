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
in
{
  options.homelab.apps.qbittorrent = {
    enable = mkEnableOption "qBittorrent homelab defaults";

    bindAddress = mkOption {
      type = types.str;
      default = if cfg.vpn.enable then config.homelab.vpn.namespace.bindAddress else "127.0.0.1";
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
      enable = mkEnableOption "run qBittorrent in shared homelab VPN namespace";
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
          serverConfig.Preferences = {
            WebUI = {
              Address = cfg.bindAddress;
              ReverseProxySupportEnabled = true;
            };
          }
          // lib.optionalAttrs cfg.vpn.enable {
            "Connection\\Interface" = config.homelab.vpn.interface.name;
            "Connection\\InterfaceName" = config.homelab.vpn.interface.name;
          };
        };

        systemd.services.qbittorrent = {
          after = lib.mkIf cfg.vpn.enable [ "vpnns-ready.service" ];
          requires = lib.mkIf cfg.vpn.enable [ "vpnns-ready.service" ];
          bindsTo = lib.mkIf cfg.vpn.enable [ "vpnns-anchor.service" ];
          serviceConfig = {
            UMask = lib.mkForce "0007";
            NoNewPrivileges = true;
            PrivateTmp = lib.mkForce true;
            PrivateDevices = true;
            DevicePolicy = "closed";
            ProtectSystem = lib.mkForce "strict";
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
              config.services.qbittorrent.profileDir
              storage.downloadsDir
            ];
            PrivateUsers = true;
            MemoryDenyWriteExecute = true;
          }
          // lib.optionalAttrs cfg.vpn.enable {
            NetworkNamespacePath = config.homelab.vpn.namespace.path;
            BindReadOnlyPaths = [ "${config.homelab.vpn.namespace.resolvConfPath}:/etc/resolv.conf" ];
          };
        };

        systemd.tmpfiles.rules = [
          "d ${config.services.qbittorrent.profileDir} 0750 ${user} ${group} - -"
        ];

        users.groups.${storage.group} = { };
        users.users.${user}.extraGroups = [ storage.group ];
      };
    in
    mkIf cfg.enable (
      lib.mkMerge [
        qbittorrentConfig
        (lib.mkIf cfg.vpn.enable {
          homelab.vpn.namespace.hostIngressPorts = {
            tcp = [ cfg.webuiPort ];
          };
        })
        (lib.mkIf (cfg.vpn.enable && cfg.vpn.allowInbound) {
          homelab.vpn.inboundPorts = {
            tcp = [ cfg.torrentingPort ];
            udp = [ cfg.torrentingPort ];
          };
        })
      ]
    );
}
