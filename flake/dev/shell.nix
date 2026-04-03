{
  perSystem =
    { pkgs, inputs', ... }:
    {
      devShells.default = pkgs.mkShellNoCC {
        packages = with pkgs; [
          nh
          just
          inputs'.agenix.packages.default

          bashInteractive
        ];
      };
    };
}
