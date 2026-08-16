# Pure-Nix rehydration of a serialized .drv closure (from `nix derivation show
# -r`), WITHOUT `nix derivation add` (no store mutation). We replay each node
# through `builtins.derivation`, re-attaching input dependencies via string
# context, so the reconstructed derivation is byte-identical to the original -
# same drvPath, same outputs - and therefore rebuildable from source on a cache
# miss. Durable: the closure JSON is the recipe; only hash-pinned source FODs
# need to persist upstream.
#
# `dump` = builtins.fromJSON of the `nix derivation show -r <drv>` output:
#   { derivations = { "<drvpath>" = <node>; ... }; }
# `srcs` = { "<store-name>" = <re-added path>; } for inlined inputSrcs (repo
# files re-added via builtins.path). Every inputSrc in the closure must be
# present; a missing one throws (no cache-dependent storePath fallback), so the
# graph is GC-proof by construction.
# Returns a function drvPath -> the rehydrated derivation value.
{
  dump,
  srcs ? { },
}:
let
  drvs = dump.derivations;
  storeDir = builtins.storeDir;

  # Auto env vars that `builtins.derivation` sets itself; never pass them back.
  autoEnv =
    node:
    [
      "name"
      "system"
      "builder"
      "outputs"
    ]
    ++ builtins.attrNames node.outputs;

  # A node's own output paths -> the self-reference placeholder Nix hashes with.
  # Original env bakes the resolved output path; derivation hashes self-refs as a
  # placeholder, so we must reverse that before handing env back. FOD outputs are
  # content-addressed (no `path`, and no self-refs), so skip them.
  selfSubst =
    node:
    builtins.concatMap (
      o:
      let
        out = node.outputs.${o};
      in
      if out ? path then
        [
          {
            from = "${storeDir}/${out.path}";
            to = builtins.placeholder o;
          }
        ]
      else
        [ ]
    ) (builtins.attrNames node.outputs);

  # Memoized fixpoint: reconstruct each node exactly once. The closure is a DAG
  # with heavy sharing (every node pulls the same bootstrap-tools/gcc/stdenv), so
  # naive recursion is exponential - inputs reference `memo`, not a re-call.
  reconNode =
    drvPath:
    let
      node = drvs.${drvPath};
      # local binding (not `node.inputs.drvs`): keeps the `inputs`-first attrpath
      # off the flake-input quoting lint, which only means flake `inputs`.
      deps = node.inputs;

      # 1. input derivations (memoized); collect their output paths as
      #    context-carrying strings (referencing the rebuilt input .drv).
      inputDrvSubst = builtins.concatLists (
        builtins.attrValues (
          builtins.mapAttrs (
            ipath: outs:
            let
              rd = memo.${ipath};
            in
            map (o: {
              from = "${(rd.${o}).outPath}"; # plain string of the input output path
              to = "${rd.${o}}"; # same string but carrying rd's derivation context
            }) outs.outputs
          ) deps.drvs
        )
      );

      # 2. inputSrcs (store-names): every one must be inlined into `srcs` (a repo
      #    file re-added via builtins.path, GC-proof). A missing one is a hard
      #    error - we never silently fall back to a cache-dependent store path.
      inputSrcSubst = map (s: {
        from = "${storeDir}/${s}";
        to = "${srcs.${s}
          or (throw "rehydrate: inputSrc '${s}' is not inlined; regenerate srcs/ (pins/rehydrated/generate.sh)")
        }";
      }) deps.srcs;

      subst = inputDrvSubst ++ inputSrcSubst ++ selfSubst node;
      froms = map (x: x.from) subst;
      tos = map (x: x.to) subst;
      recontext = v: if builtins.isString v then builtins.replaceStrings froms tos v else v;
      # structuredAttrs values are nested lists/attrs; recontext strings anywhere.
      recontextDeep =
        v:
        if builtins.isString v then
          recontext v
        else if builtins.isList v then
          map recontextDeep v
        else if builtins.isAttrs v then
          builtins.mapAttrs (_: recontextDeep) v
        else
          v;

      isFOD = (node.outputs.out or { }) ? hash;
      fodAttrs =
        if isFOD then
          {
            # SRI hash carries its own algo, so OMIT outputHashAlgo entirely.
            # Passing "" injects a spurious `outputHashAlgo` field into the .drv
            # for nar-method FODs (e.g. cargo -vendor-staging), diverging the
            # drvPath from nixpkgs. `method` ("nar"/"flat") is the exact
            # outputHashMode nixpkgs serializes, so pass it through verbatim.
            outputHash = node.outputs.out.hash;
            outputHashMode = node.outputs.out.method or "recursive";
          }
        else
          { };

      # `builtins.derivation` treats these attr names as booleans, but the .drv
      # env serializes them as "1"/"" strings - convert back or it type-errors.
      boolAttrs = [
        "__structuredAttrs"
        "preferLocalBuild"
        "allowSubstitutes"
        "__contentAddressed"
        "__impure"
      ];
      toBool = s: s == "1" || s == "true";
      userEnv0 = builtins.mapAttrs (_: recontext) (builtins.removeAttrs node.env (autoEnv node));
      userEnv =
        userEnv0
        // builtins.listToAttrs (
          map (k: {
            name = k;
            value = toBool userEnv0.${k};
          }) (builtins.filter (k: userEnv0 ? ${k}) boolAttrs)
        );
    in
    # __structuredAttrs derivations (env is outputs-only; the config lives in a
    # `structuredAttrs` field that Nix serializes to .attrs.json). Replay the
    # whole structured config with context re-attached.
    if node ? structuredAttrs then
      builtins.derivation (
        (recontextDeep node.structuredAttrs)
        // {
          __structuredAttrs = true;
          args = map recontext node.args;
        }
      )
    else
      builtins.derivation (
        {
          inherit (node) name system;
          # builder is often an input derivation's output path (e.g. a bootstrap
          # seed) - recontext it too, or that dependency edge is lost.
          builder = recontext node.builder;
          args = map recontext node.args;
        }
        # Output order matters (it's hashed into the output paths). `attrNames`
        # sorts alphabetically; the real declaration order lives in env.outputs.
        # A single "out" output is the default - passing it would add an `outputs`
        # env var the original lacks, so only set it for multi-output.
        // (
          if node.env ? outputs then
            {
              outputs = builtins.filter (s: builtins.isString s && s != "") (builtins.split " " node.env.outputs);
            }
          else
            { }
        )
        // fodAttrs
        // userEnv
      );

  # the lazy self-referential memo: each drv reconstructed at most once.
  memo = builtins.mapAttrs (drvPath: _: reconNode drvPath) drvs;
in
drvPath: memo.${drvPath}
