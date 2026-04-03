{
  config,
  lib,
  pkgs,
  ...
}:
{
  imports = [ ../../modules ];

  nixpkgs.config.allowUnfree = true;

  networking.hostName = "vm-test-vpn";
  system.stateVersion = "26.05";

  users.users.tester = {
    isNormalUser = true;
    initialPassword = "tester";
    extraGroups = [ "wheel" ];
  };

  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = true;
  };

  homelab.storage.enable = true;

  homelab.vpn = {
    enable = true;
    uplinkInterface = "eth0";

    interface = {
      privateKeyFile = "/run/secrets/homelab-vpn-privatekey";
      addressIPv4 = "10.64.0.2";
      dns = [ "1.1.1.1" ];
    };

    peer = {
      publicKey = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
      endpointHost = "198.51.100.1";
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

  systemd.tmpfiles.rules = [
    "d /run/secrets 0755 root root - -"
    "f /run/secrets/homelab-vpn-privatekey 0600 root root - AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
  ];

  virtualisation.vmVariant = {
    virtualisation = {
      host.pkgs = import pkgs.path {
        system = "aarch64-darwin";
        inherit (config.nixpkgs) config overlays;
      };

      graphics = false;
      cores = 4;
      memorySize = 8192;

      forwardPorts = [
        {
          from = "host";
          host.address = "127.0.0.1";
          host.port = 2222;
          guest.port = 22;
        }
      ];

      useNixStoreImage = lib.mkDefault false;
      useBootLoader = lib.mkDefault false;
    };

    networking.firewall.allowedTCPPorts = [ 22 ];
  };
}
