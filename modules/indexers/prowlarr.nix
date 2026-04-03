{ config, lib, ... }:
let
  inherit (lib)
    mkEnableOption
    mkIf
    mkOption
    types
    ;

  cfg = config.homelab.services.prowlarr;

  user = "prowlarr";
  group = "prowlarr";
in
{
  options.homelab.services.prowlarr = {
    enable = mkEnableOption "Prowlarr homelab defaults";

    bindAddress = mkOption {
      type = types.str;
      default = if cfg.vpn.enable then config.homelab.vpn.namespace.bindAddress else "127.0.0.1";
    };

    port = mkOption {
      type = types.port;
      default = 9696;
    };

    vpn.enable = mkEnableOption "run Prowlarr in shared homelab VPN namespace";
  };

  config =
    let
      prowlarrConfig = {
        services.prowlarr = {
          enable = true;
          settings.server = {
            inherit (cfg) bindAddress port;
            urlbase = "";
          };
        };

        users.groups.${group} = { };
        users.users.${user} = {
          isSystemUser = true;
          inherit group;
        };

        systemd.services.prowlarr = {
          after = lib.mkIf cfg.vpn.enable [ "vpnns.service" ];
          requires = lib.mkIf cfg.vpn.enable [ "vpnns.service" ];
          bindsTo = lib.mkIf cfg.vpn.enable [ "vpnns-anchor.service" ];
          unitConfig = {
            RequiresMountsFor = [
              config.services.prowlarr.dataDir
            ]
            ++ lib.optionals cfg.vpn.enable [ config.homelab.vpn.namespace.resolvConfPath ];
            JoinsNamespaceOf = lib.mkIf cfg.vpn.enable [ "vpnns-anchor.service" ];
          };
          serviceConfig =
            config.homelab.vpn.namespace.serviceHardening
            // {
              DynamicUser = lib.mkForce false;
              User = lib.mkForce user;
              Group = lib.mkForce group;
              UMask = "0007";
              RestrictAddressFamilies =
                if cfg.vpn.enable then
                  config.homelab.vpn.namespace.serviceHardening.RestrictAddressFamilies
                else
                  [
                    "AF_UNIX"
                    "AF_INET"
                  ]
                  ++ lib.optionals config.networking.enableIPv6 [ "AF_INET6" ];
              ReadWritePaths = [ config.services.prowlarr.dataDir ];
            }
            // lib.optionalAttrs cfg.vpn.enable {
              PrivateNetwork = lib.mkForce true;
              BindReadOnlyPaths = [ "${config.homelab.vpn.namespace.resolvConfPath}:/etc/resolv.conf" ];
            };
        };

        systemd.tmpfiles.rules = [ "d ${config.services.prowlarr.dataDir} 0750 ${user} ${group} - -" ];
      };
    in
    mkIf cfg.enable (
      lib.mkMerge [
        prowlarrConfig
        (lib.mkIf cfg.vpn.enable {
          homelab.vpn.namespace.hostIngressPorts = {
            tcp = [ cfg.port ];
          };
        })
      ]
    );
}
