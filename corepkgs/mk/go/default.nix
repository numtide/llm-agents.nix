# mkGo: build a Go package from source, nixpkgs-free. CGO_ENABLED=0 -> a static
# binary, no patchelf needed. Modules vendored by vendor/go (one vendorHash
# FOD; go.sum hashes aren't fetchurl-compatible). cgo = true compiles cgo C via
# zig cc -> dynamic output patchelf'd to the pinned glibc; buildInputs adds C-lib pins.
scope:
{
  pname,
  version ? null,
  src, # fetched source archive (a .tar.gz with a single top-level dir)
  vendorHash ? null, # hash of `go mod vendor` (like nixpkgs' vendorHash); null = the source commits its own in-tree vendor/ dir
  sourceRoot ? null, # subdir holding go.mod (relative to the tarball top dir)
  subPackages ? [ "." ], # package dirs to build (parallel to `binaries`)
  binaries ? [ pname ], # output binary names (parallel to `subPackages`)
  ldflags ? [ ], # extra -ldflags entries
  tags ? [ ], # -tags
  cgo ? false, # CGO_ENABLED=1: compile cgo C via zig cc; output is dynamic, patchelf'd to the pinned glibc
  buildInputs ? [ ], # C-library pins (cgo external libs) - /lib joins the rpath, /lib/pkgconfig joins PKG_CONFIG_PATH
  mainProgram ? builtins.head binaries,
  meta ? { },
  category ? null,
  updater ? null,
}:
let
  inherit (scope)
    mkDrvSh
    goVendor
    systems
    system
    pins
    toolchains
    ;
  inherit (toolchains) go zig;
  sys = systems.${system};
  gnuTarget = "${sys.zig.platform}-gnu";
  extraLibPath = builtins.concatStringsSep ":" (map (p: "${p}/lib") buildInputs);
  pkgConfigPath = builtins.concatStringsSep ":" (map (p: "${p}/lib/pkgconfig") buildInputs);
  # cgo output rpath: pinned glibc + gccLib (+ any C-lib buildInputs)
  cgoLibpath =
    "${pins.glibc}/lib:${pins.gccLib}/lib" + (if extraLibPath == "" then "" else ":${extraLibPath}");
  # null vendorHash = the module has no external deps (stdlib only); skip
  # vendoring and build offline with -mod=mod.
  vendor =
    if vendorHash == null then
      null
    else
      goVendor {
        inherit
          src
          vendorHash
          sourceRoot
          go
          ;
      };
  # subPackages and binaries are parallel; join into "pkg:bin" pairs.
  pairs = builtins.concatStringsSep " " (
    builtins.genList (i: "${builtins.elemAt subPackages i}:${builtins.elemAt binaries i}") (
      builtins.length subPackages
    )
  );
  drv = mkDrvSh {
    name = if version == null then "${pname}" else "${pname}-${version}";
    env = {
      inherit src go pairs;
      vendor = if vendor == null then "" else vendor;
      sourceRoot = if sourceRoot == null then "" else sourceRoot;
      ldflags = builtins.concatStringsSep " " ldflags;
      tags = builtins.concatStringsSep "," tags;
      useCgo = if cgo then "1" else "";
      inherit zig gnuTarget pkgConfigPath;
      cgoLibpath = if cgo then cgoLibpath else "";
      glibc = pins.glibc;
      formatelf = pins.formatelf;
      loader = sys.loader;
      pkgConfigBin = "${pins.pkgConfig}/bin";
    };
    script = ./builder.sh;
  };
in
drv
// {
  # linux-only for now. CGO_ENABLED=0 output is static; cgo output is a dynamic
  # ELF patchelf'd to the pinned glibc.
  meta = {
    platforms = [ "x86_64-linux" ];
    inherit mainProgram;
  }
  // meta;
  passthru =
    (if category == null then { } else { inherit category; })
    // (if updater == null then { } else { inherit updater; });
  fhs = {
    kind = if cgo then "patchelf" else "static";
    libpath = if cgo then cgoLibpath else "";
    inherit mainProgram;
    ignoreMissing = "";
  };
}
// (if updater == null then { } else { inherit updater; })
