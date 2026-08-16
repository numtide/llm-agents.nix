# mkPnpm: build a pnpm project from source, nixpkgs-free. Deps vendored by
# vendor/pnpm (a flat hoisted node_modules FOD, our own pnpmDepsHash). Runs
# the build script via pnpm, installs dist + node_modules under $out/lib/<pname>,
# and wraps `node <entry>`.
scope:
{
  pname,
  version,
  src, # fetched source archive (.tar.gz, single top-level dir)
  pnpmDepsHash, # our node_modules FOD hash (build once with a fake hash to obtain)
  entry, # script node runs, relative to the app root (e.g. "dist/cli.js")
  buildScript ? "build", # `pnpm run <buildScript>`; "" to skip (no build step)
  postPatch ? "", # shell run in the source before the build (e.g. a lockfile fixup)
  sourceRoot ? null, # subdir holding package.json (relative to the tarball top dir)
  mainProgram ? pname,
  meta ? { },
  category ? null,
  updater ? null,
}:
let
  inherit (scope)
    mkDrvSh
    pnpmVendor
    pins
    toolchains
    ;
  inherit (toolchains) node pnpm;
  vendor = pnpmVendor {
    inherit
      src
      pnpmDepsHash
      sourceRoot
      postPatch
      pnpm
      node
      ;
  };
  libpath = "${pins.glibc}/lib:${pins.gccLib}/lib";
  drv = mkDrvSh {
    name = "${pname}-${version}";
    env = {
      inherit
        src
        node
        pnpm
        vendor
        pname
        mainProgram
        entry
        buildScript
        postPatch
        ;
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
  fhs = {
    kind = "patchelf";
    inherit libpath mainProgram;
    ignoreMissing = "";
  };
}
// (if updater == null then { } else { inherit updater; })
