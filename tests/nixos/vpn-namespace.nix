_: {
  name = "vpn-namespace";

  nodes.machine =
    { pkgs, ... }:
    {
      imports = [ ../../modules ];

      networking.hostName = "vpn-test";
      system.stateVersion = "26.05";

      homelab.storage.enable = true;
      homelab.vpn = {
        enable = true;
        interface = {
          privateKeyFile = "/run/wg-test/private.key";
          addressIPv4 = "10.71.216.231";
          addressIPv6 = "fc00:bbbb:bbbb:bb01::8:d8e6";
          dns = [ "10.64.0.1" ];
        };
        peer = {
          publicKey = "bZQF7VRDRK/JUJ8L6EFzF/zRw2tsqMRk6FesGtTgsC0=";
          endpointHost = "138.199.43.91";
          endpointPort = 51820;
          persistentKeepalive = 25;
        };
      };

      homelab.apps.qbittorrent = {
        enable = true;
        vpn.enable = true;
      };
      homelab.apps.nzbget = {
        enable = true;
        vpn.enable = true;
      };
      homelab.services.prowlarr = {
        enable = true;
        vpn.enable = true;
      };

      environment.systemPackages = [ pkgs.nftables ];

      systemd.services.test-vpn-private-key = {
        wantedBy = [ "multi-user.target" ];
        before = [ "vpnns.service" ];
        serviceConfig.Type = "oneshot";
        script = ''
          set -eu
          ${pkgs.coreutils}/bin/mkdir -p /run/wg-test
          ${pkgs.wireguard-tools}/bin/wg genkey > /run/wg-test/private.key
          ${pkgs.coreutils}/bin/chmod 0600 /run/wg-test/private.key
          ${pkgs.coreutils}/bin/chown root:root /run/wg-test/private.key
        '';
      };
    };

  testScript = ''
    machine.wait_for_unit("multi-user.target")
    machine.wait_for_unit("vpnns-anchor.service")
    machine.wait_for_unit("vpnns.service")
    machine.wait_for_unit("qbittorrent.service")
    machine.wait_for_unit("nzbget.service")
    machine.wait_for_unit("prowlarr.service")

    machine.succeed("systemctl is-active vpnns-anchor.service")
    machine.succeed("systemctl is-active vpnns.service")

    machine.succeed("systemctl show -p JoinsNamespaceOf --value qbittorrent.service | grep -q 'vpnns-anchor.service'")
    machine.succeed("systemctl show -p JoinsNamespaceOf --value nzbget.service | grep -q 'vpnns-anchor.service'")
    machine.succeed("systemctl show -p JoinsNamespaceOf --value prowlarr.service | grep -q 'vpnns-anchor.service'")

    machine.succeed("systemctl show -p NetworkNamespacePath --value qbittorrent.service | grep -q '^$'")
    machine.succeed("systemctl show -p NetworkNamespacePath --value nzbget.service | grep -q '^$'")
    machine.succeed("systemctl show -p NetworkNamespacePath --value prowlarr.service | grep -q '^$'")

    machine.succeed("ip netns list | grep -q '^vpnapps\\b'")
    machine.succeed("ip -n vpnapps link show wg0")
    machine.succeed("ip -n vpnapps route show default dev wg0 | grep -q .")
    machine.succeed("ip -n vpnapps -6 route show default dev wg0 | grep -q .")

    machine.succeed("ip netns exec vpnapps /run/current-system/sw/bin/nft list table inet vpnns | grep -q 'chain output'")
    machine.succeed("ip netns exec vpnapps /run/current-system/sw/bin/nft list table inet vpnns | grep -q 'policy drop'")
    machine.succeed("ip netns exec vpnapps /run/current-system/sw/bin/nft list table inet vpnns | grep -q 'oifname \"wg0\" accept'")

    machine.succeed("test -s /run/vpnns/resolv.conf")
    machine.succeed("grep -q '^nameserver 10.64.0.1$' /run/vpnns/resolv.conf")
    machine.succeed("grep -q '^options edns0$' /run/vpnns/resolv.conf")
  '';
}
