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
  version = "2.7.3";
  src = fetchFromGitHub {
    owner = "dolthub";
    repo = "dolt";
    tag = "v${version}";
    hash = "sha256-r1lQHngJdoCkK3ZILsKvkN4n1IyrDtGUmv0TbsgEMXU=";
  };
  vendorHash = "sha256-/oOXX1EpStBFQOY78Eb57CUYDYIdgB0GakwHfPuBm+w=";
  passthru = (old.passthru or { }) // {
    hideFromDocs = true;
  };
})
