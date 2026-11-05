# nixpkgs ships dolt 1.x, but gascity's managed bd/Dolt runtime requires
# Dolt >= 2.1.0. Bump the nixpkgs package; dolt 2.1.2 requires go >= 1.26.2,
# newer than nixpkgs' default Go, so build with go-bin.
{
  # pkgs.dolt is used explicitly: a `dolt` argument would resolve to this
  # package itself.
  pkgs,
  buildGoModule,
  fetchFromGitHub,
  go-bin,
}:
let
  base = pkgs.dolt.override {
    buildGoModule = buildGoModule.override { go = go-bin; };
  };
in
base.overrideAttrs (old: rec {
  version = "2.7.2";
  src = fetchFromGitHub {
    owner = "dolthub";
    repo = "dolt";
    tag = "v${version}";
    hash = "sha256-HC1Yhoy4lRkrhZmZ19UfqqWJRb/ewjrdXr5+l8/TXSk=";
  };
  vendorHash = "sha256-yfXeQK26N0qu50CEo67j6Cz7ixOi9pG0Pi8Qit6P4rU=";
  passthru = (old.passthru or { }) // {
    hideFromDocs = true;
  };
})
