_: {
  perSystem =
    { pkgs, ... }:
    {
      checks.vpn-namespace = pkgs.testers.runNixOSTest (
        import ../../tests/nixos/vpn-namespace.nix { inherit pkgs; }
      );
    };
}
