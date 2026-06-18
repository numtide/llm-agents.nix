{
  pkgs,
  ...
}@args:
pkgs.callPackage ./package.nix (
  {
    mkRustyV8Archive = pkgs.callPackage ../../lib/rusty-v8.nix { };
  }
  // builtins.removeAttrs args [ "pkgs" ]
)
