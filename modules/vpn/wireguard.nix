{
  lib,
  config,
  pkgs,
  ...
}:
let
  inherit (lib)
    any
    concatStringsSep
    hasInfix
    hasPrefix
    hasSuffix
    mkAfter
    mkDefault
    mkEnableOption
    mkIf
    mkOption
    optionalAttrs
    optionals
    optionalString
    removePrefix
    removeSuffix
    types
    unique
    ;

  cfg = config.homelab.vpn;

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

  endpointHostRaw = if cfg.peer.endpointHost == null then "" else cfg.peer.endpointHost;

  endpointHost =
    if hasPrefix "[" endpointHostRaw && hasSuffix "]" endpointHostRaw then
      removeSuffix "]" (removePrefix "[" endpointHostRaw)
    else
      endpointHostRaw;

  endpointHostIsIPv4 =
    builtins.match ''^((25[0-5]|2[0-4][0-9]|1?[0-9]?[0-9])\.){3}(25[0-5]|2[0-4][0-9]|1?[0-9]?[0-9])$'' endpointHost
    != null;
  endpointHostIsIPv6 =
    builtins.match "^[0-9A-Fa-f:.]+$" endpointHost != null
    && builtins.match "^.*:.*:.*$" endpointHost != null;
  endpointHostIsIpLiteral = endpointHost != "" && (endpointHostIsIPv4 || endpointHostIsIPv6);

  endpoint =
    if endpointHostIsIPv6 then
      "[${endpointHost}]:${toString cfg.peer.endpointPort}"
    else
      "${endpointHost}:${toString cfg.peer.endpointPort}";

  wgAddresses =
    optionals useTunnelIPv4 [ "${cfg.interface.addressIPv4}/32" ]
    ++ optionals useTunnelIPv6 [ "${cfg.interface.addressIPv6}/128" ];

  peerAllowedIPs = optionals useTunnelIPv4 [ "0.0.0.0/0" ] ++ optionals useTunnelIPv6 [ "::/0" ];

  dnsHasIPv6 = any (s: hasInfix ":" s) cfg.interface.dns;
  dnsHasIPv4 = any (s: !(hasInfix ":" s)) cfg.interface.dns;

  inboundTcp = unique cfg.inboundPorts.tcp;
  inboundUdp = unique cfg.inboundPorts.udp;

  renderSet = values: "{ ${concatStringsSep ", " values} }";

  readOnlyBindMount = hostPath: {
    inherit hostPath;
    isReadOnly = true;
  };
in
{
  options.homelab.vpn = {
    enable = mkEnableOption "containerized VPN-routed app stack for selected apps";

    uplinkInterface = mkOption {
      type = types.nullOr types.str;
      default = null;
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

      bindAddress = mkOption {
        type = types.str;
        default =
          if cfg.container.localAddressIPv4 != null then
            cfg.container.localAddressIPv4
          else
            cfg.container.localAddressIPv6;
        readOnly = true;
      };
    };

    interface = {
      name = mkOption {
        type = types.str;
        default = "wg0";
      };

      privateKeyFile = mkOption {
        type = types.nullOr types.str;
        default = null;
      };

      addressIPv4 = mkOption {
        type = types.nullOr types.str;
        default = null;
      };

      addressIPv6 = mkOption {
        type = types.nullOr types.str;
        default = null;
      };

      dns = mkOption {
        type = types.listOf types.str;
        default = [ ];
      };

      mtu = mkOption {
        type = types.ints.between 1280 65535;
        default = 1420;
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
        type = types.int;
        default = 25;
      };

      presharedKeyFile = mkOption {
        type = types.nullOr types.str;
        default = null;
      };
    };

    inboundPorts = {
      tcp = mkOption {
        type = types.listOf types.port;
        default = [ ];
        description = "TCP ports that should accept inbound traffic from the VPN tunnel interface.";
      };

      udp = mkOption {
        type = types.listOf types.port;
        default = [ ];
        description = "UDP ports that should accept inbound traffic from the VPN tunnel interface.";
      };
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.uplinkInterface != null;
        message = "homelab.vpn.uplinkInterface must be set.";
      }
      {
        assertion = useTunnelIPv4 || useTunnelIPv6;
        message = "At least one of homelab.vpn.interface.addressIPv4/addressIPv6 must be set.";
      }
      {
        assertion = useOuterIPv4 || useOuterIPv6;
        message = "At least one container veth family must be configured.";
      }
      {
        assertion = cfg.peer.publicKey != null;
        message = "homelab.vpn.peer.publicKey must be set.";
      }
      {
        assertion = cfg.peer.endpointHost != null;
        message = "homelab.vpn.peer.endpointHost must be set.";
      }
      {
        assertion = cfg.peer.endpointHost == null || endpointHostIsIpLiteral;
        message = "homelab.vpn.peer.endpointHost must be an IP literal (IPv4 or IPv6), not a hostname.";
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
        assertion = endpointHost == "" || !endpointHostIsIPv6 || useOuterIPv6;
        message = "WireGuard endpointHost is IPv6, but container veth IPv6 is not configured.";
      }
      {
        assertion = endpointHost == "" || endpointHostIsIPv6 || useOuterIPv4;
        message = "WireGuard endpointHost is IPv4, but container veth IPv4 is not configured.";
      }
      {
        assertion = cfg.interface.privateKeyFile != null;
        message = "homelab.vpn.interface.privateKeyFile must be set.";
      }
      {
        assertion = cfg.interface.privateKeyFile != null && hasPrefix "/" cfg.interface.privateKeyFile;
        message = "homelab.vpn.interface.privateKeyFile must be an absolute path.";
      }
      {
        assertion = cfg.peer.presharedKeyFile == null || hasPrefix "/" cfg.peer.presharedKeyFile;
        message = "homelab.vpn.peer.presharedKeyFile must be an absolute path when set.";
      }
      {
        assertion = cfg.interface.dns != [ ];
        message = "homelab.vpn.interface.dns must be non-empty.";
      }
    ];

    boot.enableContainers = true;
    virtualisation.containers.enable = true;

    networking.networkmanager.unmanaged = mkIf config.networking.networkmanager.enable (mkAfter [
      "interface-name:ve-*"
    ]);

    networking.nat = {
      enable = true;
      internalInterfaces = lib.mkAfter [ "ve-${cfg.container.name}" ];
      externalInterface = mkDefault cfg.uplinkInterface;
      enableIPv6 = mkDefault useOuterIPv6;
    };

    systemd.tmpfiles.rules =
      optionals (cfg.interface.privateKeyFile != null) [
        "z ${cfg.interface.privateKeyFile} 0640 root systemd-network - -"
      ]
      ++ optionals (cfg.peer.presharedKeyFile != null) [
        "z ${cfg.peer.presharedKeyFile} 0640 root systemd-network - -"
      ];

    containers.${cfg.container.name} = {
      autoStart = true;
      privateNetwork = true;

      hostAddress = mkIf useOuterIPv4 cfg.container.hostAddressIPv4;
      localAddress = mkIf useOuterIPv4 cfg.container.localAddressIPv4;
      hostAddress6 = mkIf useOuterIPv6 cfg.container.hostAddressIPv6;
      localAddress6 = mkIf useOuterIPv6 cfg.container.localAddressIPv6;

      bindMounts =
        { }
        // optionalAttrs (cfg.interface.privateKeyFile != null) {
          "${cfg.interface.privateKeyFile}" = readOnlyBindMount cfg.interface.privateKeyFile;
        }
        // optionalAttrs (cfg.peer.presharedKeyFile != null) {
          "${cfg.peer.presharedKeyFile}" = readOnlyBindMount cfg.peer.presharedKeyFile;
        };

      config = {
        system.stateVersion = config.system.stateVersion;

        networking.useHostResolvConf = false;
        networking.enableIPv6 = useTunnelIPv6 || useOuterIPv6;

        networking.defaultGateway = mkIf useOuterIPv4 cfg.container.hostAddressIPv4;
        networking.defaultGateway6 = mkIf useOuterIPv6 {
          address = cfg.container.hostAddressIPv6;
          interface = "eth0";
        };

        networking.nftables.enable = true;
        networking.firewall.enable = false;

        boot.kernel.sysctl."net.ipv4.conf.all.src_valid_mark" = 1;

        systemd.network.enable = true;
        services.resolved.enable = true;

        systemd.services.vpn-ready = {
          description = "Wait for ${cfg.interface.name} VPN readiness";
          after = [ "systemd-networkd.service" ];
          requires = [ "systemd-networkd.service" ];
          wantedBy = [ "multi-user.target" ];
          serviceConfig = {
            Type = "oneshot";
          };
          script = ''
            set -eu
            ${pkgs.systemd}/lib/systemd/systemd-networkd-wait-online --interface=${cfg.interface.name} --timeout=30
            ${optionalString useTunnelIPv4 ''
              route_line_v4="$(${pkgs.iproute2}/bin/ip -o -4 route show table 51820 default dev ${cfg.interface.name})"
              [ -n "$route_line_v4" ]
            ''}
            ${optionalString useTunnelIPv6 ''
              route_line_v6="$(${pkgs.iproute2}/bin/ip -o -6 route show table 51820 default dev ${cfg.interface.name})"
              [ -n "$route_line_v6" ]
            ''}
          '';
        };

        systemd.network.config.routeTables.vpnapps = 51820;

        systemd.network.netdevs."50-${cfg.interface.name}" = {
          netdevConfig = {
            Name = cfg.interface.name;
            Kind = "wireguard";
            MTUBytes = cfg.interface.mtu;
          };

          wireguardConfig = {
            FirewallMark = 51820;
          }
          // optionalAttrs (cfg.interface.privateKeyFile != null) {
            PrivateKeyFile = cfg.interface.privateKeyFile;
          };

          wireguardPeers = optionals (cfg.peer.publicKey != null && endpointHostIsIpLiteral) [
            (
              {
                PublicKey = cfg.peer.publicKey;
                Endpoint = endpoint;
                AllowedIPs = peerAllowedIPs;
                RouteTable = 51820;
                PersistentKeepalive = cfg.peer.persistentKeepalive;
              }
              // optionalAttrs (cfg.peer.presharedKeyFile != null) {
                PresharedKeyFile = cfg.peer.presharedKeyFile;
              }
            )
          ];
        };

        systemd.network.networks."50-${cfg.interface.name}" = {
          matchConfig.Name = cfg.interface.name;
          address = wgAddresses;
          inherit (cfg.interface) dns;
          domains = [ "~." ];

          networkConfig = {
            ConfigureWithoutCarrier = true;
            IgnoreCarrierLoss = true;
            DNSDefaultRoute = true;
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

              ${optionalString useOuterIPv4 ''
                iifname "eth0" ip saddr ${cfg.container.hostAddressIPv4} accept
              ''}
              ${optionalString useOuterIPv6 ''
                iifname "eth0" ip6 saddr ${cfg.container.hostAddressIPv6} accept
              ''}
              ${optionalString (inboundTcp != [ ]) ''
                iifname "${cfg.interface.name}" tcp dport ${renderSet (map toString inboundTcp)} accept
              ''}
              ${optionalString (inboundUdp != [ ]) ''
                iifname "${cfg.interface.name}" udp dport ${renderSet (map toString inboundUdp)} accept
              ''}
            }

            chain output {
              type filter hook output priority filter; policy drop;

              oifname "lo" accept
              ct state established,related accept

              oifname "eth0" meta mark 51820 accept
              oifname "${cfg.interface.name}" accept
            }
          '';
        };
      };
    };
  };
}
