{ inputs, ... }:
{
  flake.nixosConfigurations.vm-test-vpn = inputs.nixpkgs.lib.nixosSystem {
    system = "aarch64-linux";
    specialArgs = { inherit inputs; };
    modules = [
      ../../hosts/vm-test-vpn/default.nix
    ];
  };
}
