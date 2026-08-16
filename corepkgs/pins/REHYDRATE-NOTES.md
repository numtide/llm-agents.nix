# Pure-Nix .drv rehydration — prototype findings

Goal: make the standalone (nixpkgs-free) pins **rebuildable from source** instead
of appendContext store-path references that dead-end when cache.nixos.org GCs
them. Approach: serialize a pin's `.drv` closure (`nix derivation show -r`) and
replay it in **pure Nix** (no `nix derivation add`, no store mutation) via
`builtins.derivation` + `builtins.appendContext`, landing the identical drvPath.

## What works (see `rehydrate.nix`)

Reconstructs a node by re-attaching input dependencies as string context and
handing the result to `builtins.derivation`. Verified to reproduce the **exact
drvPath** for, in order of the bugs found and fixed:

1. no-input derivations — but only if you DON'T pass `outputs=["out"]` (that adds
   an `outputs` env var the default single-output derivation lacks).
1. multi-node closures with inter-dependencies (context via `replaceStrings`).
1. self-references (`$out` in args/env) — reverse the resolved output path back
   to `builtins.placeholder`.
1. FOD-with-inputs (`hex0`, the stage0 seed) — but the **`builder`** field must
   be recontexted too, or the seed dependency edge is dropped.
1. multi-output order — the real order is `env.outputs` ("out bin"), not
   `attrNames` (sorted).
1. `preferLocalBuild`/`allowSubstitutes`/`__structuredAttrs` serialize as "1"/""
   strings but `builtins.derivation` wants bools.
1. FOD `outputHashAlgo` — the output hash is SRI (`sha256-…`, self-describing),
   so `outputHashAlgo` must be **omitted**. Passing `""` injects a spurious
   field into the `.drv` for `method = "nar"` FODs (cargo `-vendor-staging`),
   diverging the drvPath. `method` maps straight to `outputHashMode`.

Performance: **must memoize** — the closure is a DAG with heavy sharing
(bootstrap-tools/gcc/stdenv), so naive recursion is exponential (9 min → 0.4 s
with a lazy fixpoint memo).

Result: the **entire pin closure — all 1206 nodes — reproduces the exact
nixpkgs drvPath** (byte-identical `.drv`, not just matching pin outputs). So the
rehydrated backend is 100% compatible with nixpkgs at the derivation level, and
every one of the 20 pins lands the identical output store path.

## The "minimal-env" nodes: it's `__structuredAttrs` (handleable)

5/400 nodes (`libunistring`, `libxcrypt`, `python3-minimal`, `which`, `xgcc`)
have a `.drv` whose `env` is **only the output paths**. First read as a wall,
but the v4 JSON has a top-level `structuredAttrs` field carrying the full config
(src/stdenv/buildInputs/…): these packages set `__structuredAttrs = true` in
their nixpkgs `package.nix` (stdenv defaults it off:
`structuredAttrsByDefault = config.structuredAttrsByDefault or false`). For
structuredAttrs, Nix passes attrs via a generated `.attrs.json`, so the env is
minimal *by design*. Early adopters of nixpkgs' migration; the count grows over
time.

`builtins.derivation { __structuredAttrs = true; … }` reproduces that shape
(verified — minimal env, `structuredAttrs` set). So the fix is: for a
structuredAttrs node, recontext its `structuredAttrs` field recursively (strings
in nested lists/attrs get input/self context) and pass it plus
`__structuredAttrs = true`. Then pure-Nix rehydration is **complete (400/400)** —
TODO in `rehydrate.nix` (currently handles the 395 classic-env nodes).

## Source files: what has to be inlined to be GC-proof

The closure's leaves are two kinds:

- **FOD tarballs (114 nodes):** upstream source (glibc/gcc/…), fetched **by
  hash**. Already durable — refetchable from anywhere.
- **inputSrcs (293 files for the full pin set, 104 of them glibc's):** the
  `"${./patch}"` / `builtins.path` interpolations — patches, CVE fixes, setup
  hooks (`add-flags.sh`, `audit-tmpdir.sh`, `default-builder.sh`), `.m4` macros.
  These are nixpkgs source-tree files, NOT fetchable by URL.

**Done:** all inputSrcs are inlined into `rehydrated/srcs/` and re-added by
content via `builtins.path` (or `builtins.toFile` for text FODs) → identical
store path. `rehydrate.nix` has **no `builtins.storePath` fallback**: a src that
is not inlined throws, so the graph is GC-proof by construction. The standalone
flake is now self-contained: rehydrated `.drv` graph + committed patch/hook
files + hash-fetched upstream tarballs. Nothing depends on cache retention.
Measured cost of inlining vs the old store-ref path: **none** (within eval
noise; see `bench-eval.nu`).

## Status: done and wired (`rehydrated.nix`)

Pure-Nix rehydration is complete — no `nix derivation add`, no store mutation —
and shipped as the **default nixpkgs-free pins backend** (`corepkgs/default.nix`
selects `pins/rehydrated.nix` when no `pkgs` is passed). Both prior TODOs done:

1. structuredAttrs nodes: recursive recontext of the `structuredAttrs` field
   plus `__structuredAttrs = true` (`rehydrate.nix`).
1. inlined inputSrcs: `rehydrated/srcs/` holds all 293 files, re-added by content
   via `builtins.path` (or `builtins.toFile` for text FODs — auto-selected by
   which method reproduces the store name). The executable bit is preserved in
   the committed copy because it is part of the NAR hash.

`rehydrated/` = the serialized data: `closure.json` (the combined `.drv` graph
for the 20 non-formatelf pins, keyed by store-name), `manifest.json`
(pin -> {drv, output}), `srcs/` (inlined inputSrcs), and `generate.sh` (rerun on
a nixpkgs/pin bump). Verified: all 20 rehydrated pins reproduce the exact store
path of `pins/pkgs.nix`, and a pin (`zlib`) **builds from source** through the
replayed graph. `formatelf` (rust closure, not serialized) and non-x86_64-linux
systems fall through to `closure.nix`.
