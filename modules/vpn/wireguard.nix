{
  lib,
  config,
  pkgs,
  ...
}:
let
  inherit (lib)
    any
    concatMapStringsSep
    concatStringsSep
    hasInfix
    hasPrefix
    hasSuffix
    mkEnableOption
    mkIf
    mkOption
    optionalString
    optionals
    removePrefix
    removeSuffix
    types
    ;

  cfg = config.homelab.vpn;

  useTunnelIPv4 = cfg.interface.addressIPv4 != null;
  useTunnelIPv6 = cfg.interface.addressIPv6 != null;

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

  dnsHasIPv6 = any (s: hasInfix ":" s) cfg.interface.dns;
  dnsHasIPv4 = any (s: !(hasInfix ":" s)) cfg.interface.dns;

  inboundTcp = lib.unique cfg.inboundPorts.tcp;
  inboundUdp = lib.unique cfg.inboundPorts.udp;
  hostIngressTcp = lib.unique cfg.namespace.hostIngressPorts.tcp;
  hostIngressUdp = lib.unique cfg.namespace.hostIngressPorts.udp;

  namespacePath = "/run/netns/${cfg.namespace.name}";
  bindAddress = cfg.namespace.veth.nsAddressIPv4;

  dnsLines = concatMapStringsSep "\n" (dnsIp: "nameserver ${dnsIp}") cfg.interface.dns;

  renderSet = values: "{ ${concatStringsSep ", " values} }";

  wgAddressCmds =
    optionals useTunnelIPv4 [
      "${pkgs.iproute2}/bin/ip -n ${cfg.namespace.name} address replace ${cfg.interface.addressIPv4}/32 dev ${cfg.interface.name}"
    ]
    ++ optionals useTunnelIPv6 [
      "${pkgs.iproute2}/bin/ip -n ${cfg.namespace.name} address replace ${cfg.interface.addressIPv6}/128 dev ${cfg.interface.name}"
    ];

  defaultRouteCmds =
    optionals useTunnelIPv4 [
      "${pkgs.iproute2}/bin/ip -n ${cfg.namespace.name} route replace default dev ${cfg.interface.name}"
    ]
    ++ optionals useTunnelIPv6 [
      "${pkgs.iproute2}/bin/ip -n ${cfg.namespace.name} -6 route replace default dev ${cfg.interface.name}"
    ];

  nftNamespaceRules = ''
    flush ruleset

    table inet vpnns {
      chain input {
        type filter hook input priority filter; policy drop;

        iifname "lo" accept
        ct state established,related accept

        ${optionalString (hostIngressTcp != [ ])
          "iifname \"${cfg.namespace.veth.nsIf}\" ip saddr ${cfg.namespace.veth.hostAddressIPv4} tcp dport ${renderSet (map toString hostIngressTcp)} accept"
        }
        ${optionalString (hostIngressUdp != [ ])
          "iifname \"${cfg.namespace.veth.nsIf}\" ip saddr ${cfg.namespace.veth.hostAddressIPv4} udp dport ${renderSet (map toString hostIngressUdp)} accept"
        }

        ${optionalString (
          inboundTcp != [ ]
        ) "iifname \"${cfg.interface.name}\" tcp dport ${renderSet (map toString inboundTcp)} accept"}
        ${optionalString (
          inboundUdp != [ ]
        ) "iifname \"${cfg.interface.name}\" udp dport ${renderSet (map toString inboundUdp)} accept"}
      }

      chain output {
        type filter hook output priority filter; policy drop;

        oifname "lo" accept
        ct state established,related accept

        oifname "${cfg.interface.name}" accept
      }
    }
  '';
in
{
  options.homelab.vpn = {
    enable = mkEnableOption "shared netns VPN-routed app stack for selected apps";

    uplinkInterface = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "enp3s0";
    };

    container.bindAddress = mkOption {
      type = types.str;
      default = config.homelab.vpn.namespace.bindAddress;
      readOnly = true;
      description = "Compatibility alias to homelab.vpn.namespace.bindAddress.";
    };

    namespace = {
      name = mkOption {
        type = types.str;
        default = "vpnapps";
      };

      path = mkOption {
        type = types.str;
        default = namespacePath;
        readOnly = true;
      };

      bindAddress = mkOption {
        type = types.str;
        default = bindAddress;
        readOnly = true;
      };

      resolvConfPath = mkOption {
        type = types.str;
        default = "/run/vpnns/resolv.conf";
      };

      veth = {
        hostIf = mkOption {
          type = types.str;
          default = "ve-vpn-host";
        };

        nsIf = mkOption {
          type = types.str;
          default = "ve-vpn-ns";
        };

        hostAddressIPv4 = mkOption {
          type = types.str;
          default = "10.231.0.1";
        };

        nsAddressIPv4 = mkOption {
          type = types.str;
          default = "10.231.0.2";
        };
      };

      hostIngressPorts = {
        tcp = mkOption {
          type = types.listOf types.port;
          default = [ ];
          description = "TCP ports allowed from host veth into protected namespace services.";
        };

        udp = mkOption {
          type = types.listOf types.port;
          default = [ ];
          description = "UDP ports allowed from host veth into protected namespace services.";
        };
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

    systemd.tmpfiles.rules =
      optionals (cfg.interface.privateKeyFile != null) [
        "z ${cfg.interface.privateKeyFile} 0640 root root - -"
      ]
      ++ optionals (cfg.peer.presharedKeyFile != null) [
        "z ${cfg.peer.presharedKeyFile} 0640 root root - -"
      ]
      ++ [
        "d /run/netns 0755 root root - -"
        "d /run/vpnns 0755 root root - -"
      ];

    systemd.services.vpnns-anchor = {
      description = "Namespace owner for VPN-protected services";
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${pkgs.coreutils}/bin/sleep infinity";
        PrivateNetwork = true;
      };
    };

    systemd.services.vpnns-attach = {
      description = "Attach anchor namespace to /run/netns";
      wantedBy = [ "multi-user.target" ];
      after = [ "vpnns-anchor.service" ];
      requires = [ "vpnns-anchor.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        set -eu
        pid="$(${pkgs.systemd}/bin/systemctl show -p MainPID --value vpnns-anchor.service)"
        if [ -z "$pid" ] || [ "$pid" = "0" ]; then
          echo "vpnns-anchor MainPID unavailable" >&2
          exit 1
        fi

        ${pkgs.coreutils}/bin/mkdir -p /run/netns

        if [ -e "${namespacePath}" ]; then
          ${pkgs.iproute2}/bin/ip netns del ${cfg.namespace.name} || true
        fi

        ${pkgs.iproute2}/bin/ip netns attach ${cfg.namespace.name} "$pid"
        ${pkgs.iproute2}/bin/ip -n ${cfg.namespace.name} link set lo up
      '';
    };

    systemd.services.vpnns-link = {
      description = "Create host-vpn namespace veth link";
      wantedBy = [ "multi-user.target" ];
      after = [ "vpnns-attach.service" ];
      requires = [ "vpnns-attach.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        set -eu

        ${pkgs.iproute2}/bin/ip link del ${cfg.namespace.veth.hostIf} 2>/dev/null || true

        ${pkgs.iproute2}/bin/ip link add ${cfg.namespace.veth.hostIf} type veth peer name ${cfg.namespace.veth.nsIf}
        ${pkgs.iproute2}/bin/ip link set ${cfg.namespace.veth.nsIf} netns ${cfg.namespace.name}

        ${pkgs.iproute2}/bin/ip addr replace ${cfg.namespace.veth.hostAddressIPv4}/30 dev ${cfg.namespace.veth.hostIf}
        ${pkgs.iproute2}/bin/ip link set ${cfg.namespace.veth.hostIf} up

        ${pkgs.iproute2}/bin/ip -n ${cfg.namespace.name} addr replace ${cfg.namespace.veth.nsAddressIPv4}/30 dev ${cfg.namespace.veth.nsIf}
        ${pkgs.iproute2}/bin/ip -n ${cfg.namespace.name} link set ${cfg.namespace.veth.nsIf} up
      '';
    };

    systemd.services.vpnns-wg = {
      description = "Create and configure WireGuard inside vpn namespace";
      wantedBy = [ "multi-user.target" ];
      after = [ "vpnns-link.service" ];
      requires = [ "vpnns-link.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        set -eu

        ${pkgs.iproute2}/bin/ip -n ${cfg.namespace.name} link del ${cfg.interface.name} 2>/dev/null || true
        ${pkgs.iproute2}/bin/ip link del ${cfg.interface.name} 2>/dev/null || true

        ${pkgs.iproute2}/bin/ip link add ${cfg.interface.name} type wireguard
        ${pkgs.iproute2}/bin/ip link set ${cfg.interface.name} netns ${cfg.namespace.name}

        ${pkgs.iproute2}/bin/ip netns exec ${cfg.namespace.name} ${pkgs.wireguard-tools}/bin/wg set ${cfg.interface.name} \
          private-key ${cfg.interface.privateKeyFile} \
          listen-port 0 \
          peer ${cfg.peer.publicKey} \
          endpoint ${endpoint} \
          persistent-keepalive ${toString cfg.peer.persistentKeepalive} \
          allowed-ips ${
            if useTunnelIPv4 && useTunnelIPv6 then
              "0.0.0.0/0,::/0"
            else if useTunnelIPv4 then
              "0.0.0.0/0"
            else
              "::/0"
          }

        ${optionalString (cfg.peer.presharedKeyFile != null) ''
          ${pkgs.iproute2}/bin/ip netns exec ${cfg.namespace.name} ${pkgs.wireguard-tools}/bin/wg set ${cfg.interface.name} preshared-key ${cfg.peer.presharedKeyFile}
        ''}

        ${concatStringsSep "\n" wgAddressCmds}

        ${pkgs.iproute2}/bin/ip -n ${cfg.namespace.name} link set ${cfg.interface.name} mtu ${toString cfg.interface.mtu}
        ${pkgs.iproute2}/bin/ip -n ${cfg.namespace.name} link set ${cfg.interface.name} up

        ${concatStringsSep "\n" defaultRouteCmds}
      '';
    };

    systemd.services.vpnns-dns = {
      description = "Write dedicated resolver configuration for VPN namespace services";
      wantedBy = [ "multi-user.target" ];
      after = [ "vpnns-link.service" ];
      requires = [ "vpnns-link.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        set -eu
        ${pkgs.coreutils}/bin/mkdir -p "$(${pkgs.coreutils}/bin/dirname ${cfg.namespace.resolvConfPath})"
        ${pkgs.coreutils}/bin/cat > ${cfg.namespace.resolvConfPath} <<'EOF'
        ${dnsLines}
        options edns0
        EOF
        ${pkgs.coreutils}/bin/chmod 0444 ${cfg.namespace.resolvConfPath}
      '';
    };

    systemd.services.vpnns-firewall = {
      description = "Load fail-closed nftables rules for VPN namespace";
      wantedBy = [ "multi-user.target" ];
      after = [
        "vpnns-wg.service"
        "vpnns-link.service"
      ];
      requires = [
        "vpnns-wg.service"
        "vpnns-link.service"
      ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        set -eu
        ${pkgs.iproute2}/bin/ip netns exec ${cfg.namespace.name} ${pkgs.nftables}/bin/nft -f - <<'EOF'
        ${nftNamespaceRules}
        EOF
      '';
    };

    systemd.services.vpnns-ready = {
      description = "Verify vpn namespace readiness";
      wantedBy = [ "multi-user.target" ];
      after = [
        "vpnns-attach.service"
        "vpnns-link.service"
        "vpnns-wg.service"
        "vpnns-dns.service"
        "vpnns-firewall.service"
      ];
      requires = [
        "vpnns-attach.service"
        "vpnns-link.service"
        "vpnns-wg.service"
        "vpnns-dns.service"
        "vpnns-firewall.service"
      ];
      serviceConfig = {
        Type = "oneshot";
      };
      script = ''
        set -eu
        [ -e "${namespacePath}" ]
        ${pkgs.iproute2}/bin/ip -n ${cfg.namespace.name} link show ${cfg.interface.name}
        ${pkgs.iproute2}/bin/ip -n ${cfg.namespace.name} route show default dev ${cfg.interface.name} | ${pkgs.gnugrep}/bin/grep -q .
        ${pkgs.iproute2}/bin/ip netns exec ${cfg.namespace.name} ${pkgs.wireguard-tools}/bin/wg show ${cfg.interface.name}
        [ -s ${cfg.namespace.resolvConfPath} ]
        ${pkgs.iproute2}/bin/ip netns exec ${cfg.namespace.name} ${pkgs.nftables}/bin/nft list ruleset | ${pkgs.gnugrep}/bin/grep -q "table inet vpnns"
      '';
    };
  };
}
