{ inputs, ... }:
{
  imports = [
    ./nixos.nix
    ./formatter.nix
    ./git-hooks.nix
    ./shell.nix
  ];

  systems = import inputs.systems;
}
