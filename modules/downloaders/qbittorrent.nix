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
          after = lib.mkIf cfg.vpn.enable [ "vpnns.service" ];
          requires = lib.mkIf cfg.vpn.enable [ "vpnns.service" ];
          bindsTo = lib.mkIf cfg.vpn.enable [ "vpnns-anchor.service" ];
          unitConfig = {
            RequiresMountsFor = [
              config.services.qbittorrent.profileDir
              storage.downloadsDir
            ]
            ++ lib.optionals cfg.vpn.enable [ config.homelab.vpn.namespace.resolvConfPath ];
            JoinsNamespaceOf = lib.mkIf cfg.vpn.enable [ "vpnns-anchor.service" ];
          };
          serviceConfig =
            config.homelab.vpn.namespace.serviceHardening
            // {
              UMask = lib.mkForce "0007";
              NoNewPrivileges = lib.mkForce true;
              PrivateTmp = lib.mkForce true;
              PrivateDevices = lib.mkForce true;
              ProtectSystem = lib.mkForce "strict";
              ProtectHome = lib.mkForce true;
              RestrictAddressFamilies =
                if cfg.vpn.enable then
                  config.homelab.vpn.namespace.serviceHardening.RestrictAddressFamilies
                else
                  [
                    "AF_UNIX"
                    "AF_INET"
                  ]
                  ++ lib.optionals config.networking.enableIPv6 [ "AF_INET6" ];
              ReadWritePaths = [
                config.services.qbittorrent.profileDir
                storage.downloadsDir
              ];
              PrivateUsers = true;
              MemoryDenyWriteExecute = true;
            }
            // lib.optionalAttrs cfg.vpn.enable {
              PrivateNetwork = lib.mkForce true;
              BindReadOnlyPaths = [ "${config.homelab.vpn.namespace.resolvConfPath}:/etc/resolv.conf" ];
            };
        };

        systemd.tmpfiles.rules = [
          "d ${config.services.qbittorrent.profileDir} 0750 ${user} ${group} - -"
        ];

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
