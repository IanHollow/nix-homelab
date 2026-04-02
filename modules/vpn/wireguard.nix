{ lib, config, ... }:
let
  inherit (lib)
    mkEnableOption
    mkIf
    mkOption
    mkDefault
    types
    optionals
    optionalString
    optionalAttrs
    mkMerge
    concatStringsSep
    hasInfix
    any
    ;

  cfg = config.homelab.vpnAppStack;

  useTunnelIPv4 = cfg.interface.addressIPv4 != null;
  useTunnelIPv6 = cfg.interface.addressIPv6 != null;

  family =
    if useTunnelIPv4 && useTunnelIPv6 then
      "both"
    else if useTunnelIPv4 then
      "ipv4"
    else if useTunnelIPv6 then
      "ipv6"
    else
      throw "addressIPv4 and addressIPv6 cannot both be null";

  useOuterIPv4 = cfg.container.hostAddressIPv4 != null && cfg.container.localAddressIPv4 != null;

  useOuterIPv6 = cfg.container.hostAddressIPv6 != null && cfg.container.localAddressIPv6 != null;

  endpointIsIPv6 = hasInfix ":" cfg.peer.endpointHost;

  endpoint =
    if endpointIsIPv6 then
      "[${cfg.peer.endpointHost}]:${toString cfg.peer.endpointPort}"
    else
      "${cfg.peer.endpointHost}:${toString cfg.peer.endpointPort}";

  wgAddresses =
    optionals useTunnelIPv4 [ "${cfg.interface.addressIPv4}/32" ]
    ++ optionals useTunnelIPv6 [ "${cfg.interface.addressIPv6}/128" ];

  peerAllowedIPs = optionals useTunnelIPv4 [ "0.0.0.0/0" ] ++ optionals useTunnelIPv6 [ "::/0" ];

  serviceListenAddress =
    if useOuterIPv4 then cfg.container.localAddressIPv4 else cfg.container.localAddressIPv6;

  dnsHasIPv6 = any (s: hasInfix ":" s) cfg.interface.dns;
  dnsHasIPv4 = any (s: !(hasInfix ":" s)) cfg.interface.dns;

  webPorts =
    optionals cfg.services.nzbget.enable [ cfg.services.nzbget.port ]
    ++ optionals cfg.services.prowlarr.enable [ cfg.services.prowlarr.port ]
    ++ optionals cfg.services.qbittorrent.enable [ cfg.services.qbittorrent.webuiPort ];

  renderSet = values: "{ ${concatStringsSep ", " values} }";

  commonServiceHardening = rwPaths: {
    NoNewPrivileges = true;
    PrivateTmp = true;
    ProtectSystem = "strict";
    ProtectHome = true;
    ProtectControlGroups = true;
    ProtectKernelModules = true;
    ProtectKernelTunables = true;
    RestrictRealtime = true;
    RestrictSUIDSGID = true;
    LockPersonality = true;
    SystemCallArchitectures = "native";
    UMask = "0007";
    ReadWritePaths = rwPaths;
  };

  bindMount = hostPath: {
    inherit hostPath;
    isReadOnly = false;
  };
in
{
  options.homelab.vpnAppStack = {
    enable = mkEnableOption "containerized VPN-routed app stack for NZBGet, Prowlarr, and qBittorrent";

    uplinkInterface = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Host interface that reaches the Internet before the VPN tunnel is up.";
      example = "enp3s0";
    };

    container = {
      name = mkOption {
        type = types.str;
        default = "vpn-media";
      };

      hostAddressIPv4 = mkOption {
        type = types.nullOr types.str;
        default = "10.231.0.1";
      };

      localAddressIPv4 = mkOption {
        type = types.nullOr types.str;
        default = "10.231.0.2";
      };

      hostAddressIPv6 = mkOption {
        type = types.nullOr types.str;
        default = null;
      };

      localAddressIPv6 = mkOption {
        type = types.nullOr types.str;
        default = null;
      };
    };

    interface = {
      name = mkOption {
        type = types.str;
        default = "wg0";
        description = "Name of the WireGuard interface to create on the host.";
      };

      privateKeyFile = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Absolute path to the WireGuard private key file on the host; it will be bind-mounted read-only into the container.";
      };

      addressIPv4 = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Tunnel IPv4 address without prefix length.";
      };

      addressIPv6 = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Tunnel IPv6 address without prefix length.";
      };

      dns = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "DNS servers that must be reachable through the WireGuard tunnel.";
      };

      mtu = mkOption {
        type = types.nullOr (types.ints.between 1280 65535);
        default = null;
      };
    };

    peer = {
      publicKey = mkOption {
        type = types.nullOr types.str;
        default = null;
      };

      endpointHost = mkOption {
        type = types.nullOr types.str;
        default = null;
      };

      endpointPort = mkOption {
        type = types.port;
        default = 51820;
      };

      persistentKeepalive = mkOption {
        type = types.ints;
        default = 25;
        description = "WireGuard PersistentKeepalive in seconds; 0 disables it.";
      };
    };

    storage = {
      downloadsDir = mkOption {
        type = types.str;
        default = "/srv/media/downloads";
      };
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.uplinkInterface != null;
        message = "homelab.vpnAppStack.uplinkInterface must be set to the host interface that reaches the Internet before the VPN tunnel is up.";
      }
      {
        assertion = useTunnelIPv4 || useTunnelIPv6;
        message = "At least one of homelab.vpnAppStack.interface.addressIPv4/addressIPv6 must be set.";
      }
      {
        assertion = useOuterIPv4 || useOuterIPv6;
        message = "At least one container veth family must be configured.";
      }
      {
        assertion = !(useTunnelIPv4 && !useTunnelIPv6 && dnsHasIPv6);
        message = "Tunnel is IPv4-only, so do not configure IPv6 DNS servers.";
      }
      {
        assertion = !(useTunnelIPv6 && !useTunnelIPv4 && dnsHasIPv4);
        message = "Tunnel is IPv6-only, so do not configure IPv4 DNS servers.";
      }
      {
        assertion = !endpointIsIPv6 || useOuterIPv6;
        message = "WireGuard endpointHost is IPv6, but container.hostAddressIPv6/localAddressIPv6 are not configured.";
      }
      {
        assertion = endpointIsIPv6 || useOuterIPv4;
        message = "WireGuard endpointHost is IPv4, but container.hostAddressIPv4/localAddressIPv4 are not configured.";
      }
      {
        assertion = cfg.interface.privateKeyFile != null;
        message = "homelab.vpnAppStack.interface.privateKeyFile must be set to the absolute path of the WireGuard private key file on the host.";
      }
      {
        assertion = cfg.interface.dns != [ ];
        message = "homelab.vpnAppStack.interface.dns must be non-empty.";
      }
    ];

    boot.enableContainers = true;
    virtualisation.containers.enable = true;

    networking.nat = {
      enable = true;
      internalInterfaces = lib.mkAfter [ "ve-${cfg.container.name}" ];
      externalInterface = mkDefault cfg.uplinkInterface;
      enableIPv6 = mkDefault useOuterIPv6;
    };

    # Persistent host-side directories for bind mounts.
    systemd.tmpfiles.rules = [
      "d ${cfg.storage.downloadsDir} 0750 root root - -"
    ]
    ++ optionals config.services.nzbget.enable [
      "d ${config.services.nzbget.dataDir} 0750 root root - -"
    ]
    ++ optionals config.services.prowlarr.enable [
      "d ${config.services.prowlarr.dataDir} 0750 root root - -"
    ]
    ++ optionals config.services.qbittorrent.enable [
      "d ${config.services.qbittorrent.profileDir} 0750 root root - -"
    ];

    containers.${cfg.container.name} = {
      autoStart = true;
      privateNetwork = true;

      hostAddress = mkIf useOuterIPv4 cfg.container.hostAddressIPv4;
      localAddress = mkIf useOuterIPv4 cfg.container.localAddressIPv4;
      hostAddress6 = mkIf useOuterIPv6 cfg.container.hostAddressIPv6;
      localAddress6 = mkIf useOuterIPv6 cfg.container.localAddressIPv6;

      bindMounts = {
        "${cfg.interface.privateKeyFile}" = {
          hostPath = cfg.interface.privateKeyFile;
          isReadOnly = true;
        };

        "${cfg.storage.downloadsDir}" = bindMount cfg.storage.downloadsDir;
      }
      // optionalAttrs config.services.nzbget.enable { "/var/lib/nzbget" = bindMount "/var/lib/nzbget"; }
      // optionalAttrs config.services.prowlarr.enable {
        "${config.services.prowlarr.dataDir}" = bindMount config.services.prowlarr.dataDir;
      }
      // optionalAttrs config.services.qbittorrent.enable {
        "${config.services.qbittorrent.profileDir}" = bindMount config.services.qbittorrent.profileDir;
      };

      config =
        let
          mainConfig = config;
        in
        { lib, config, ... }:
        {
          system.stateVersion = mainConfig.system.stateVersion;

          networking.useHostResolvConf = false;
          networking.nameservers = cfg.interface.dns;
          networking.enableIPv6 = useTunnelIPv6 || useOuterIPv6;

          networking.defaultGateway = mkIf useOuterIPv4 cfg.container.hostAddressIPv4;
          networking.defaultGateway6 = mkIf useOuterIPv6 {
            address = cfg.container.hostAddressIPv6;
            interface = "eth0";
          };

          networking.nftables.enable = true;
          networking.firewall.enable = false;

          systemd.network.enable = true;
          services.resolved.enable = false;

          systemd.network.config.routeTables.vpnapps = 51820;

          systemd.network.netdevs."50-${cfg.interface.name}" = {
            netdevConfig = {
              Name = cfg.interface.name;
              Kind = "wireguard";
            }
            // optionalAttrs (cfg.interface.mtu != null) { MTUBytes = cfg.interface.mtu; };

            wireguardConfig = {
              PrivateKeyFile = cfg.interface.privateKeyFile;
              FirewallMark = 51820;
            };

            wireguardPeers = [
              {
                PublicKey = cfg.peer.publicKey;
                Endpoint = endpoint;
                AllowedIPs = peerAllowedIPs;
                RouteTable = 51820;
                PersistentKeepalive = cfg.persistentKeepalive;
              }
            ];
          };

          systemd.network.networks."50-${cfg.interface.name}" = {
            matchConfig.Name = cfg.interface.name;
            address = wgAddresses;

            linkConfig.RequiredForOnline = false;

            networkConfig = {
              ConfigureWithoutCarrier = true;
              IgnoreCarrierLoss = true;
            };

            routingPolicyRules = [
              {
                Family = family;
                Table = "main";
                SuppressPrefixLength = 0;
                Priority = 10000;
              }
              {
                Family = family;
                FirewallMark = 51820;
                InvertRule = true;
                Table = 51820;
                Priority = 10001;
              }
            ];
          };

          networking.nftables.tables.vpn-killswitch = {
            family = "inet";
            content = ''
              chain input {
                type filter hook input priority filter; policy drop;

                iifname "lo" accept
                ct state established,related accept

                ${optionalString (useOuterIPv4 && webPorts != [ ]) ''
                  iifname "eth0" ip saddr ${cfg.container.hostAddressIPv4} tcp dport ${renderSet (map toString webPorts)} accept
                ''}
                ${optionalString (useOuterIPv6 && webPorts != [ ]) ''
                  iifname "eth0" ip6 saddr ${cfg.container.hostAddressIPv6} tcp dport ${renderSet (map toString webPorts)} accept
                ''}
              }

              chain output {
                type filter hook output priority filter; policy drop;

                oifname "lo" accept
                ct state established,related accept

                # Allow only the outer WireGuard handshake to escape on eth0.
                ${
                  if endpointIsIPv6 then
                    ''
                      oifname "eth0" ip6 daddr ${cfg.peer.endpointHost} udp dport ${toString cfg.peer.endpointPort} accept
                    ''
                  else
                    ''
                      oifname "eth0" ip daddr ${cfg.peer.endpointHost} udp dport ${toString cfg.peer.endpointPort} accept
                    ''
                }

                # Everything else must go through the tunnel.
                oifname "${cfg.interface.name}" accept
              }
            '';
          };

          services.nzbget = mkIf config.services.nzbget.enable {
            enable = true;
            settings = {
              ControlIP = serviceListenAddress;
            };
          };

          services.prowlarr = mkIf config.services.prowlarr.enable {
            enable = true;
            settings.server = {
              bindaddress = serviceListenAddress;
            };
          };

          services.qbittorrent = mkIf config.services.qbittorrent.enable {
            enable = true;
            webuiPort = 8081;
            torrentingPort = 51413;
            serverConfig.Preferences.WebUI = {
              Address = serviceListenAddress;
              ReverseProxySupportEnabled = true;
            };
          };

          users.groups = mkMerge [
            (optionalAttrs config.services.nzbget.enable { "${config.services.nzbget.group}" = { }; })
            (optionalAttrs config.services.prowlarr.enable { prowlarr = { }; })
            (optionalAttrs config.services.qbittorrent.enable { "${config.services.qbittorrent.group}" = { }; })
          ];

          users.users = mkMerge [
            (optionalAttrs config.services.prowlarr.enable {
              prowlarr = {
                isSystemUser = true;
                group = "prowlarr";
              };
            })
          ];

          systemd.services = mkMerge [
            (mkIf config.services.nzbget.enable {
              nzbget.serviceConfig = commonServiceHardening [
                "/var/lib/nzbget"
                cfg.storage.downloadsDir
              ];
            })

            (mkIf config.services.prowlarr.enable {
              prowlarr.serviceConfig = (commonServiceHardening [ config.services.prowlarr.dataDir ]) // {
                DynamicUser = lib.mkForce false;
                User = lib.mkForce "prowlarr";
                Group = lib.mkForce "prowlarr";
              };
            })

            (mkIf config.services.qbittorrent.enable {
              qbittorrent.serviceConfig = commonServiceHardening [
                config.services.qbittorrent.profileDir
                cfg.storage.downloadsDir
              ];
            })
          ];
        };
    };
  };
}
