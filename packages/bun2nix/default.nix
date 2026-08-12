{
  flake,
  pkgs,
  ...
}:
# bun2nix CLI from the flake input, exposed so CI pushes it to the binary
# cache and update jobs don't have to build it from source (crates.io
# rejects nix's crate downloads with 403).
let
  bun2nix = flake.inputs."bun2nix".packages.${pkgs.stdenv.hostPlatform.system}.bun2nix;
in
bun2nix
// {
  passthru = (bun2nix.passthru or { }) // {
    hideFromDocs = true;
  };
}
