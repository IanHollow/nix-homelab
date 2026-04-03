{ config, pkgs, ... }:
{
  imports = [ ../../modules ];

  nixpkgs.config.allowUnfree = true;

  networking.hostName = "vm-test-vpn";
  system.stateVersion = "26.05";

  users.users.tester = {
    isNormalUser = true;
    initialPassword = "tester";
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIC4EqEGMCbdAeSwbmcjzSHtpuhUPOAp+IjOjNaGlhC4v"
    ];
  };

  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = true;
  };

  age.identityPaths = [ "/var/lib/agenix-identity/home-server-vm" ];
  age.secrets.homelab-vpn-privatekey = {
    file = ../../secrets/homelab-vpn-privatekey.age;
    owner = "root";
    group = "root";
    mode = "0400";
  };

  homelab.storage.enable = true;

  homelab.vpn = {
    enable = true;
    uplinkInterface = "eth0";

    interface = {
      privateKeyFile = config.age.secrets.homelab-vpn-privatekey.path;
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

      sharedDirectories.host-secrets = {
        source = ''"''${VM_AGE_IDENTITY_DIR:?set VM_AGE_IDENTITY_DIR}"'';
        target = "/var/lib/agenix-identity";
        securityModel = "none";
      };
    };

    networking.firewall.allowedTCPPorts = [ 22 ];
  };
}
