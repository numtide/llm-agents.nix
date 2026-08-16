# Build the memoized module tree from the registry. A nixpkgs-free fixed point:
# each module is `scope: X`, and we pass the whole (lazy) tree, so a module
# selects its deps by name - no path-import, no per-call rewiring. Every module
# evaluates at most once (attr values in the fixed point are memoized), so this
# is one shared tree, not a callPackage that re-derives deps on every call.
#
# `system` and `pins` are ambient scalars. `toolchains` defaults to the registry
# provider (derived from the -bin packages in-scope); pass one to override it -
# the bootstrap seam (a from-source toolchain is a provider swap, no module edits).
{
  system,
  pins,
  toolchains ? null,
}:
let
  registry = import ./registry.nix;
  fix =
    f:
    let
      x = f x;
    in
    x;
in
fix (
  final:
  builtins.mapAttrs (_name: path: import path final) registry
  // {
    inherit system pins;
  }
  // (if toolchains == null then { } else { inherit toolchains; })
)
