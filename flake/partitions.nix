{ inputs, ... }:
{
  imports = [ inputs.flake-parts.flakeModules.partitions ];

  partitionedAttrs = {
    apps = "dev";
    checks = "dev";
    devShells = "dev";
    formatter = "dev";
    nixosConfigurations = "dev";
  };

  partitions = {
    dev = {
      extraInputsFlake = ./dev;
      module.imports = [ ./dev ];
    };
  };
}
