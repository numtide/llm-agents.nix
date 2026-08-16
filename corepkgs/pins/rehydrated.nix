# Third pins backend: durable, source-rebuildable pins via pure-Nix .drv
# rehydration (see rehydrate.nix + REHYDRATE-NOTES.md).
#
# closure.nix pins are `builtins.appendContext` store-path refs: pure at eval,
# but a dead end once cache.nixos.org GCs them (a bare path, no recipe). This
# backend instead replays a *serialized* `.drv` closure (rehydrated/closure.json)
# in pure Nix, so every pin carries its full from-source build graph and stays
# buildable on a total cache miss. The only things that must persist are:
#   - hash-pinned upstream source FODs (refetchable from any mirror), and
#   - the nixpkgs source-tree files (patches/hooks) that aren't URL-fetchable -
#     those are inlined into rehydrated/srcs/ and re-added here via builtins.path
#     (identical store path by content), so nothing depends on cache retention.
#
# x86_64-linux only (that is what the closure was serialized for). Every other
# system - and formatelf, whose rust closure we don't serialize - falls through
# to closure.nix unchanged.
system:
let
  fallback = import ./closure.nix system;
in
if system != "x86_64-linux" then
  fallback
else
  let
    dump = builtins.fromJSON (builtins.readFile ./rehydrated/closure.json);
    # pin name -> { drv = "<store-name>.drv"; output = "out"|"dev"|"lib"|...; }
    manifest = builtins.fromJSON (builtins.readFile ./rehydrated/manifest.json);

    # Re-add every inlined inputSrc by content, reproducing its exact store path.
    # Two ways a source entered the store, hashed differently:
    #   - `builtins.path` / filtered source -> recursive NAR hash. Passing the
    #     original name-part (store name minus the 32-char hash and dash) with
    #     the file content reproduces the path.
    #   - `builtins.toFile` / writeText -> flat `text:sha256` hash. NAR-hashing
    #     it (builtins.path) yields a different path, so fall back to toFile.
    # The reproduced store name is deterministic, so we can just pick whichever
    # method lands the original name - no per-file method table needed.
    srcDir = ./rehydrated/srcs;
    reAdd =
      s:
      let
        nm = builtins.substring 33 (builtins.stringLength s) s;
        viaPath = builtins.path {
          path = srcDir + "/${s}";
          name = nm;
        };
      in
      if builtins.baseNameOf viaPath == s then
        viaPath
      else
        builtins.toFile nm (builtins.readFile (srcDir + "/${s}"));
    srcs = builtins.listToAttrs (
      map (s: {
        name = s;
        value = reAdd s;
      }) (builtins.attrNames (builtins.readDir srcDir))
    );

    rehydrate = import ./rehydrate.nix { inherit dump srcs; };
  in
  fallback // builtins.mapAttrs (_: m: (rehydrate m.drv).${m.output}.outPath) manifest
