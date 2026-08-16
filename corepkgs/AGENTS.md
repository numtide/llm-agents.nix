# corepkgs — Agent Guidelines

corepkgs is this repo's **nixpkgs-free packaging system**. It builds tools with
no nixpkgs and no stdenv at build time, using a truly-static nushell as the
builder. The standalone flake (`corepkgs/flake.nix`) has **zero inputs**.

## Consumer contract (important)

A consumer (the root `flake.nix`, checks, scripts) must reach corepkgs **only
through the entry point** — `core = import ./corepkgs { ... }` — and then use
`core.*`. **Never path-import a file under `corepkgs/`** (no
`import ./corepkgs/lib/foo.nix`, no `readDir ./corepkgs/packages`). corepkgs owns
its layout; the consumer owns supplying nixpkgs deps to the functions it exposes.

## Internal wiring: registry + memoized scope

Inside corepkgs, **no module path-imports a sibling either.** `registry.nix`
maps every module name to its file (the ONE place that knows the layout).
`scope.nix` builds a nixpkgs-free fixed point over it: each module is
`scope: X`, and it names its deps with `inherit (scope) mkDrvSh fetchurl systems system pins toolchains …` instead of `import ../foo.nix`. The tree is **memoized**
(a fixed-point attr value evaluates once; callers just select attrs) — deliberately
NOT a per-call `callPackage`/`intersectAttrs`, which would re-derive deps on every
`mkCargo {…}`/`fetchurl {…}`. Leaves that need nothing from the tree take `_scope:`
(`fetch/interpolate.nix`, `seed/systems.nix`, `lib/*`). `system`/`pins`/`toolchains`
are ambient scalars in the scope; `default.nix` is a thin view selecting scope
members into `lib`/`packages`. **Adding/moving a module = edit `registry.nix` +
give the file a `scope:` head; nothing else changes.** Constructors expose their
user args as the second layer (`scope: { pname, … }: drv`), so `core.lib.mkCargo`
is the already-scoped `{ pname, … }: drv` — the consumer API is unchanged.

The surface:

- `core.lib` — the builder API + primitives: `mkPackage`, `mkCargo`, `mkGo`,
  `mkNpm`, `mkBun`, `mkPnpm`, `mkPython`, `mkDrvNu`, `mkDrvSh`, `checkFhs`, `coreFetchurl`,
  `interpolate`, `fetchurlTemplate`, `platformSource`, and the meta helpers
  `mkUpdater` / `mkUpdateScript` / `flakeLib` (un-called functions — the consumer
  passes its own `lib`/tools/`inputs`).
- `core.pins` — prebuilt C libraries + tools.
- `core.toolchains` — the compilers/runtimes we build with.
- `core.packages` — corepkgs' own buildable outputs (toolchains + `hello`).
- `core.machinery` — corepkgs' own by-name packages that the consumer
  `callPackage`s into its scope: helpers (formatelf, wrapBuddy, buildNpmPackage,
  versionCheckHomeHook) and tools (nixfmt-rs, the repo's Nix formatter, built via
  mkCargo). Any non-`-bin` dir under `packages/` is picked up here.
- `core.system`.

## Two seed layers, both swappable providers

corepkgs' only external dependency is two threaded "seed" attrsets, each a
default arg you can override without touching a constructor:

- **`pins`** — prebuilt C libs/tools (glibc, gccLib, openssl, zlib, formatelf,
  ...). Default: `pins/closure.nix`, which references the exact store paths via
  `builtins.appendContext` (the nixpkgs-multiverse "fast mode" trick) — pure,
  nixpkgs-free, and cache-free at eval (no narinfo fetch; paths are substituted
  from cache.nixos.org / cache.numtide.com at build time). When the root passes
  `pkgs`, `pins/pkgs.nix` reuses it (so CI can rebuild pins from source on a cache
  miss). Regenerate the paths in `pins/closure.nix` **and** `pins/store.nix` on a
  nixpkgs/formatelf bump.
- **`toolchains`** — rust, go, node, zig, bun, pnpm, python (+ seed). Default:
  `toolchains/default.nix` (the provider), which imports the prebuilt toolchain
  packages from `packages/<name>-bin/` (bun-bin, rust-bin, …). Each `-bin`
  package reads its version + per-system hash from its own `hashes.json`; the
  provider maps them to logical keys (`rust`, `go`, …) so constructors are
  untouched. `core.packages` exposes them under the `-bin` names.

Swapping either provider is the **bootstrap seam** — e.g. a from-source /
GNU Mes bootstrap is a provider swap, no constructor changes.

## Builder scripts live in `builder.sh`

Each from-source constructor and vendorer is a **directory**:
`mk/<name>/{default.nix, builder.sh}` and `vendor/<name>/{default.nix, builder.sh}`. `default.nix` computes the derivation and passes the build script
as a path — `script = ./builder.sh` — so the script is a real, syntax-
highlighted file that treefmt **shellcheck**s and **shfmt**s. `mkDrvSh` /
`mkDrvNu` accept `script` as an inline string OR a path (readFile'd). Values
reach the script only through `env` (no Nix `${}` interpolation in a raw `.sh`);
Nix-computed shell fragments (a git-source config block, rendered bin wrappers)
are passed as env vars and `eval`'d. The `.sh` files carry `set -eu` from the
mkDrvSh prelude (not visible standalone), so they open with
`# shellcheck disable=SC2154,SC2164` (env vars; cd-guarded-by-set-e).

The two **nushell** builders (`mk/package.nix` mkPackage, `mk/check-fhs.nix`)
stay inline single files: nushell resolves variables at parse time, so a
standalone `.nu` referencing the prelude's `$attrs`/`$out` fails `nu-check`, and
nushell has no formatter anyway (only parse-check). No extraction benefit.

`mkDrvSh` builds a **FOD** when given `outputHash` (+ `outputHashMode`,
default recursive) — the deps vendorers use this, so they route through mkDrvSh
instead of hand-rolling `derivation {}` with a duplicated busybox prelude.

## Constructors and the FOD hash pattern

- `mkPackage` — prebuilt binaries (patchelf/loader/wrap).
- `mkCargo` — rust from source. Per-crate crates.io FODs from `Cargo.lock`
  (**no** vendorHash; the lock's sha256s drive + verify fetches). Knobs:
  `openssl`, `buildInputs`, `cargoBuildFlags`, `extraEnv`, `gitDeps` (github-
  archive git-source vendorer for repo-root crates).
- `mkGo` — go from source. One `vendorHash` FOD (== nixpkgs' byte-for-byte —
  reuse existing hashes). `cgo = true` for cgo C via zig cc.
- `mkNpm` — npm from source. `node_modules` FOD (OUR `npmDepsHash`). Knobs:
  `packageLock` (inject a committed lock), `binWrappers`, `nativeAddons`
  (patchelf bundled `.node`), `omitOptional`.
- `mkBun` — bun from source. `node_modules` FOD (OUR `bunDepsHash`); installs
  app + node_modules and wraps `bun run <entry>`. NOT `bun build --compile` (the
  bun runs via the glibc loader, so process.execPath is the loader and
  --compile fails BunSectionNotFound; bun can't be patchelf'd either). Optional
  `buildScript` for a pre-run asset/dist build.
- `mkPnpm` — pnpm from source. Flat hoisted `node_modules` FOD (OUR
  `pnpmDepsHash`, `--config.node-linker=hoisted`); runs `pnpm run <buildScript>`
  then wraps `node <entry>`. The pnpm toolchain is the pnpm JS bundle on node.
  Copies node_modules with `cp -r` (NOT `-L`) to keep pnpm's relative `.bin`
  symlinks intact. **Multi-member pnpm workspaces are NOT supported**: a member's
  build needs sibling members linked into node_modules, but pnpm links them via
  `../packages/<member>` symlinks that point outside node_modules and don't
  survive the self-contained vendor (tsc then fails `Cannot find module @scope/<sibling>`). Single-package workspaces (`packages: ["."]`) are fine.
  `pnpm prune --prod` / `pnpm deploy` also don't work — they re-resolve against
  the pnpm store, which the hoisted vendor doesn't keep.
- `mkPython` — python app from source. `pip install --target` FOD
  (OUR `pythonDepsHash`); wraps `[project.scripts]`. Manylinux-wheel deps OK.

**Computing a FOD hash:** write the package with a placeholder
(`sha256-AAAA...=`), run `nix build --no-link .#<pkg> 2>&1 | grep -oP 'got:\s+\Ksha256-\S+'`, and paste it in. Never compute the hash from a separate
`--expr` with shell-escaped args (the escaping diverges from the real
package.nix and yields a stale hash).

**version + hashes live in `packages/<name>/hashes.json`, NOT inline** (the file
nix-update bumps). `package.nix` does `let data = builtins.fromJSON (builtins.readFile ./hashes.json);` and reads `data.version`, `data.hash` (src), and any deps hash
(`data.vendorHash` / `npmDepsHash` / `bunDepsHash` / `pnpmDepsHash` /
`pythonDepsHash`), threading `${data.version}` into the src url + meta.changelog.
Same for the `-bin` toolchains.

## FHS check

`checkFhs` asserts a package output is **store-only** — no host loader, every
NEEDED lib resolves inside /nix/store. It expands `$ORIGIN`, so manylinux wheels
that bundle private libs in a `*.libs/` sibling dir pass.

## Porting a package (workflow)

Read the nixpkgs recipe → get the source archive hash (`nix store prefetch-file`) + the lock/deps → write `packages/<name>/package.nix` on the
matching constructor → compute the FOD hash from the build's `got:` line →
`nix build .#<name>` + `.#checks.<system>.fhs-<name>` → **revert on failure**
(`git checkout -- packages/<name>/package.nix`) to keep the tree green.

Recurring **real** blockers (not worth forcing): system C libs not pinned
(onnxruntime/alsa/libvips), workspace-member git deps (cargo), heavy native
bundles (keytar/sharp/torch-CUDA), sdist-C-compile (python), exotic build tools
(rusty_v8/cmake/`zig build`).

## Layout

The top-level holds only the entry points (`default.nix`, `flake.nix`), the
wiring (`registry.nix` = name->path, `scope.nix` = the memoized tree) + docs;
everything else is a directory:

`mk/` constructors (drv-nu.nix, drv-sh.nix, package.nix, check-fhs.nix +
`<name>/{default.nix,builder.sh}` per source constructor) · `vendor/` dep
vendorers (`<name>/{default.nix,builder.sh}`) · `toolchains/default.nix` (the
provider) · `fetch/` (owned fetch primitives) · `lib/` (meta helpers) ·
`packages/` (machinery helpers + the `-bin` toolchain packages) · `pins/`
(pkgs/store/closure providers) · `seed/` (`default.nix` = the busybox+nushell
seed, `systems.nix` = per-arch platform tokens + rust triples).
