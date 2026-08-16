# mkBun: build a bun project from source, nixpkgs-free. Deps vendored by
# vendor/bun (a node_modules FOD, our own bunDepsHash). Installs app +
# node_modules under $out/lib/<pname> and wraps `bun run <entry>`.
#
# NOT `bun build --compile`: it reads process.execPath to find its base binary,
# but the toolchain runs via the pinned glibc loader (execPath = the loader), so
# --compile fails BunSectionNotFound - and bun can't be patchelf'd (its tail-
# appended runtime breaks on any ELF rewrite). Such packages stay on nixpkgs.
# Bundled prebuilt *.node addons are patchelf'd to the pinned glibc.
scope:
{
  pname,
  version,
  src, # fetched source archive (.tar.gz, single top-level dir)
  bunDepsHash, # our node_modules FOD hash (build once with a fake hash to obtain)
  entry, # script bun runs, relative to the app root (e.g. "src/index.ts")
  buildScript ? null, # optional pre-run build, `bun <buildScript>` (e.g. a tailwind/asset step)
  sourceRoot ? null, # subdir holding package.json (relative to the tarball top dir)
  mainProgram ? pname,
  meta ? { },
  category ? null,
  updater ? null,
}:
let
  inherit (scope)
    mkDrvSh
    bunVendor
    pins
    toolchains
    ;
  inherit (toolchains) bun;
  vendor = bunVendor {
    inherit
      src
      bunDepsHash
      sourceRoot
      bun
      ;
  };
  # native addon rpath: pinned glibc + gccLib (libstdc++/libgcc_s for *.node)
  libpath = "${pins.glibc}/lib:${pins.gccLib}/lib";
  drv = mkDrvSh {
    name = "${pname}-${version}";
    env = {
      inherit
        src
        bun
        vendor
        pname
        mainProgram
        entry
        ;
      buildScript = if buildScript == null then "" else buildScript;
      sourceRoot = if sourceRoot == null then "" else sourceRoot;
      formatelf = pins.formatelf;
      inherit libpath;
    };
    script = ./builder.sh;
  };
in
drv
// {
  meta = {
    platforms = [ "x86_64-linux" ];
    inherit mainProgram;
  }
  // meta;
  passthru =
    (if category == null then { } else { inherit category; })
    // (if updater == null then { } else { inherit updater; });
  # $out has no ELF of its own; any bundled *.node addon is patchelf'd to the
  # pinned glibc, and the bun runtime it runs on is already store-only.
  fhs = {
    kind = "patchelf";
    inherit libpath mainProgram;
    ignoreMissing = "";
  };
}
// (if updater == null then { } else { inherit updater; })
