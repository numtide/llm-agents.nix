# corepkgs as a standalone flake, so `nix build ./corepkgs#packages.<system>.hello`
# works on its own. The root flake does NOT consume this - it imports ./default.nix
# directly (fast eval, no locked path input). This flake is only for using corepkgs
# by itself. Zero inputs: pins come from pins/closure.nix and every package fetches
# via coreFetchurl, so no nixpkgs input is needed.
{
  description = "corepkgs — a nixpkgs-free packaging system (static seed + nushell builder)";

  outputs =
    { ... }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      # local genAttrs so we need no nixpkgs.lib
      eachSystem =
        f:
        builtins.listToAttrs (
          map (s: {
            name = s;
            value = f s;
          }) systems
        );
      # pkgs omitted -> default.nix uses the nixpkgs-free fetchClosure pins
      coreFor = system: import ./. { inherit system; };
    in
    {
      lib = eachSystem (system: (coreFor system).lib);
      packages = eachSystem (system: (coreFor system).packages);
    };
}
