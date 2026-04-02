{ lib, config, ... }:
let
  cfg = config.homelab.vpn;

  useIPv4 = cfg.interface.addressIPv4 != null;
  useIPv6 = cfg.interface.addressIPv6 != null;

  family =
    if useIPv4 && useIPv6 then
      "both"
    else if useIPv4 then
      "ipv4"
    else if useIPv6 then
      "ipv6"
    else
      throw "homelab.vpn.interface.addressIPv4 and addressIPv6 cannot both be null";

  wgAddresses =
    lib.optionals useIPv4 [ "${cfg.interface.addressIPv4}/32" ]
    ++ lib.optionals useIPv6 [ "${cfg.interface.addressIPv6}/128" ];

  peerAllowedIPs = lib.optionals useIPv4 [ "0.0.0.0/0" ] ++ lib.optionals useIPv6 [ "::/0" ];

  indexOf =
    needle: haystack:
    let
      go =
        idx: rest:
        if rest == [ ] then
          throw "User ${needle} not found in homelab.vpn.users"
        else if builtins.head rest == needle then
          idx
        else
          go (idx + 1) (builtins.tail rest);
    in
    go 0 haystack;

  mkUserRoutingRules =
    user:
    let
      basePriority = 30000 + (indexOf user cfg.users * 10);
    in
    [
      {
        User = user;
        Family = family;
        Table = "main";
        SuppressPrefixLength = 0;
        Priority = basePriority;
      }
      {
        User = user;
        Family = family;
        Table = cfg.table;
        Priority = basePriority + 1;
      }
    ];

  renderSet = values: "{ ${lib.concatStringsSep ", " values} }";

  mkKillSwitchRules = user: ''
    meta skuid ${user} oifname "${cfg.interface.name}" counter accept
    ${lib.optionalString (useIPv4 && cfg.bypassIPv4Cidrs != [ ]) ''
      meta skuid ${user} ip daddr ${renderSet cfg.bypassIPv4Cidrs} counter accept
    ''}
    ${lib.optionalString (useIPv6 && cfg.bypassIPv6Cidrs != [ ]) ''
      meta skuid ${user} ip6 daddr ${renderSet cfg.bypassIPv6Cidrs} counter accept
    ''}
    meta skuid ${user} counter drop
  '';
in
{
  options.homelab.vpn = {
    enable = lib.mkEnableOption "route selected service users through WireGuard";

    routeHostDnsViaVpn = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Route the host resolver's default DNS traffic over the WireGuard link
        using systemd-resolved (Domains=~. + DNSDefaultRoute=true).

        This is the simple, leak-resistant choice on a shared host, but it
        affects DNS for the whole machine, not only homelab.vpn.users.
      '';
    };

    persistentKeepalive = lib.mkOption {
      type = lib.types.ints.between 0 65535;
      default = 25;
      description = "WireGuard PersistentKeepalive in seconds; 0 disables it.";
    };

    table = lib.mkOption {
      type = lib.types.ints.between 1 4294967295;
      default = 51820;
      description = "Dedicated routing table for VPN-routed services.";
    };

    users = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Usernames whose traffic should be routed through the VPN.";
    };

    interface.name = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "WireGuard interface name.";
    };

    interface.privateKeyFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Absolute path to the WireGuard private key file.";
    };

    interface.addressIPv4 = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Local WireGuard IPv4 address, without prefix length.";
    };

    interface.addressIPv6 = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Local WireGuard IPv6 address, without prefix length.";
    };

    interface.dns = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "DNS servers reachable over the WireGuard tunnel.";
    };

    peer.publicKey = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "WireGuard peer public key.";
    };

    peer.endpoint = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Peer endpoint in host:port or IP:port form.

        If routeHostDnsViaVpn = true, prefer a literal IP endpoint so that
        tunnel DNS does not have to resolve the endpoint hostname.
      '';
    };

    bypassIPv4Cidrs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "127.0.0.0/8"
        "169.254.0.0/16"
      ];
      description = ''
        IPv4 destinations allowed to bypass the VPN for homelab.vpn.users.
        Keep this minimal. Add your exact LAN prefix only if you intentionally
        want cleartext LAN access.
      '';
    };

    bypassIPv6Cidrs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "::1/128"
        "fe80::/10"
      ];
      description = ''
        IPv6 destinations allowed to bypass the VPN for homelab.vpn.users.
        Keep this minimal. Add your exact ULA/LAN prefix only if you intentionally
        want cleartext LAN access.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.interface.name != null;
        message = "homelab.vpn.interface.name must be set when homelab.vpn.enable = true";
      }
      {
        assertion = cfg.interface.privateKeyFile != null;
        message = "homelab.vpn.interface.privateKeyFile must be set when homelab.vpn.enable = true";
      }
      {
        assertion = useIPv4 || useIPv6;
        message = "At least one of homelab.vpn.interface.addressIPv4/addressIPv6 must be set";
      }
      {
        assertion = cfg.peer.publicKey != null;
        message = "homelab.vpn.peer.publicKey must be set when homelab.vpn.enable = true";
      }
      {
        assertion = cfg.peer.endpoint != null;
        message = "homelab.vpn.peer.endpoint must be set when homelab.vpn.enable = true";
      }
      {
        assertion = (!cfg.routeHostDnsViaVpn) || (cfg.interface.dns != [ ]);
        message = "homelab.vpn.interface.dns must be non-empty when routeHostDnsViaVpn = true";
      }
    ];

    systemd.network.enable = true;
    services.resolved.enable = lib.mkDefault true;

    networking.firewall.checkReversePath = lib.mkDefault "loose";
    networking.nftables.enable = true;

    systemd.network.config.routeTables.wg-services = cfg.table;

    systemd.network.netdevs."50-${cfg.interface.name}" = {
      netdevConfig = {
        Name = cfg.interface.name;
        Kind = "wireguard";
      };

      wireguardConfig = {
        PrivateKeyFile = cfg.interface.privateKeyFile;
      };

      wireguardPeers = [
        {
          PublicKey = cfg.peer.publicKey;
          Endpoint = cfg.peer.endpoint;
          AllowedIPs = peerAllowedIPs;
          RouteTable = cfg.table;
          PersistentKeepalive = cfg.persistentKeepalive;
        }
      ];
    };

    systemd.network.networks."50-${cfg.interface.name}" = {
      matchConfig.Name = cfg.interface.name;

      address = wgAddresses;

      # Avoid boot being considered "offline" if the tunnel is not up yet.
      linkConfig.RequiredForOnline = false;

      dns = lib.optionals cfg.routeHostDnsViaVpn cfg.interface.dns;
      domains = lib.optionals cfg.routeHostDnsViaVpn [ "~." ];

      networkConfig = {
        ConfigureWithoutCarrier = true;
        IgnoreCarrierLoss = true;
      }
      // lib.optionalAttrs cfg.routeHostDnsViaVpn { DNSDefaultRoute = true; };

      routingPolicyRules = lib.concatMap mkUserRoutingRules cfg.users;
    };

    networking.nftables.tables.vpn-services = {
      family = "inet";
      content = ''
        chain output_filter {
          type filter hook output priority filter;
          policy accept;

          ${lib.concatStringsSep "\n          " (map mkKillSwitchRules cfg.users)}
        }
      '';
    };
  };
}
