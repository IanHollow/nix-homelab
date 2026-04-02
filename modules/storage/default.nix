{ lib, config, ... }:
let
  inherit (lib)
    hasPrefix
    mkEnableOption
    mkIf
    mkOption
    types
    ;

  cfg = config.homelab.storage;
in
{
  options.homelab.storage = {
    enable = mkEnableOption "shared storage layout for homelab services";

    downloadsDir = mkOption {
      type = types.str;
      default = "/srv/media/downloads";
      description = "Shared downloads directory used by downloader and indexer stacks.";
    };

    group = mkOption {
      type = types.str;
      default = "media";
      description = "Shared group granted write access to shared media paths.";
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = hasPrefix "/" cfg.downloadsDir;
        message = "homelab.storage.downloadsDir must be an absolute path.";
      }
    ];

    users.groups.${cfg.group} = { };

    systemd.tmpfiles.rules = [ "d ${cfg.downloadsDir} 2770 root ${cfg.group} - -" ];
  };
}
