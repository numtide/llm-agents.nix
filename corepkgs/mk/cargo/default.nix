# mkCargo: build a Rust package from source, nixpkgs-free. rust toolchain +
# `zig cc` as linker + crates vendored by vendor/cargo.
#
# zig cc can't take --dynamic-linker (it re-sub-compiles glibc/compiler_rt, which
# inherit and reject the flag), so link normally and POST-LINK patch each
# executable with formatelf (store loader + rpath) to run without /lib64.
#
# Handles pure-crates.io Cargo.lock deps. C-lib pins (buildInputs/openssl) and
# github-archive gitDeps are supported; -sys crates needing unpinned system libs
# and workspace-member git deps are not.
scope:
{
  pname,
  version ? null,
  src, # fetched source archive (a .tar.gz with a single top-level dir)
  cargoLock, # path to the package's Cargo.lock
  patches ? [ ], # patch files applied (patch -p1) in the source before the build
  sourceRoot ? null, # subdir of the source tree holding the workspace/crate (relative to the tarball's top dir), e.g. "rust" / "src-tauri"
  binaries ? [ pname ], # binaries to install from target/release/
  cargoBuildFlags ? [ ], # e.g. [ "--no-default-features" "--features" "x" "-p" "sub" ]
  buildInputs ? [ ], # extra C-library pins whose /lib joins the link path + runtime rpath (for -sys crates linking a system lib)
  # git deps Cargo.lock pins to a github repo whose ROOT is a single crate. Each:
  # { crate; source = "<Cargo.lock source string>"; hash = "<SRI of github archive
  # at the resolved rev>"; }. Workspace-member git deps (crate in a subdir) aren't
  # handled.
  gitDeps ? [ ],
  openssl ? false, # convenience: wire the pinned openssl (OPENSSL_NO_VENDOR + LIB/INCLUDE dirs) for openssl-sys / native-tls
  extraEnv ? { }, # extra build-time env vars reaching cargo/build.rs (RUSTC_BOOTSTRAP, a build.rs data path, a version override, ...)
  mainProgram ? builtins.head binaries,
  # Package metadata carried onto the bare derivation (like mkPackage).
  meta ? { },
  category ? null,
  updater ? null,
  hideFromDocs ? false, # build tools / helpers, not agent packages: skip the README + meta-completeness category
}:
let
  inherit (scope)
    mkDrvSh
    cargoVendor
    fetchurl
    systems
    system
    pins
    toolchains
    ;
  sys = systems.${system};
  isDarwin = builtins.match ".*-darwin" system != null;
  inherit (toolchains) rust zig;

  # zig cc target: <triple>-gnu on linux, the macos token (aarch64-macos) on darwin.
  gnuTarget = if isDarwin then sys.zig.platform else "${sys.zig.platform}-gnu";
  rustGnu = sys.rust.gnu; # cargo [target.<triple>]

  # Parse a git dep's Cargo.lock source string for the vendorer + config.toml.
  # source = "git+<url>[?rev=|?branch=|?tag=<v>]#<resolved-rev>".
  parseGit =
    g:
    let
      m = builtins.match "git\\+(https://[^?#]+)(\\?([^#]*))?#(.*)" g.source;
      url = builtins.elemAt m 0;
      query = builtins.elemAt m 2; # e.g. "rev=abc" / "branch=x" / null
      rev = builtins.elemAt m 3; # resolved commit (the #fragment)
      sourceKey = "git+${url}" + (if query == null then "" else "?${query}");
      kv = if query == null then null else builtins.match "(rev|branch|tag)=(.*)" query;
      fieldLine = if kv == null then "" else "${builtins.elemAt kv 0} = \"${builtins.elemAt kv 1}\"";
    in
    {
      inherit (g) crate;
      inherit
        url
        rev
        sourceKey
        fieldLine
        ;
      archive = fetchurl {
        url = "${url}/archive/${rev}.tar.gz";
        hash = g.hash;
        name = "${g.crate}-${rev}.tar.gz";
      };
    };
  gits = map parseGit gitDeps;
  # a [source."..."] replacement block per git dep, all pointing at the vendor dir
  gitConfig = builtins.concatStringsSep "\n" (
    map (
      g:
      ''
        [source."${g.sourceKey}"]
        git = "${g.url}"
      ''
      + (if g.fieldLine == "" then "" else g.fieldLine + "\n")
      + ''
        replace-with = "vendored"
      ''
    ) gits
  );
  vendor = cargoVendor {
    inherit cargoLock;
    gitDeps = map (g: { inherit (g) crate archive; }) gits;
  };
  # extra C-library pins (buildInputs + openssl) whose /lib joins the link path
  # and the runtime rpath so -sys crates linking a system lib resolve it.
  # C-lib pins (buildInputs/openssl) are linux-only; darwin dyld-links libSystem.
  extraLibs = if isDarwin then [ ] else buildInputs ++ (if openssl then [ pins.openssl ] else [ ]);
  extraLibPath = builtins.concatStringsSep ":" (map (p: "${p}/lib") extraLibs);
  # the zcc post-link sets rpath to the pinned glibc + gccLib (+ extra C libs)
  libpath =
    if isDarwin then
      ""
    else
      "${pins.glibc}/lib:${pins.gccLib}/lib" + (if extraLibPath == "" then "" else ":${extraLibPath}");
  drv = mkDrvSh {
    name = if version == null then "${pname}" else "${pname}-${version}";
    env = {
      inherit
        src
        vendor
        rust
        zig
        rustGnu
        gnuTarget
        gitConfig # [source."..."] git-dep replacement blocks
        ;
      installBins = builtins.concatStringsSep " " binaries;
      patchFiles = builtins.concatStringsSep " " patches;
      buildFlags = builtins.concatStringsSep " " cargoBuildFlags;
      cargoLockFile = cargoLock; # copied over the source's lock so the vendored lock is authoritative
      sourceRoot = if sourceRoot == null then "" else sourceRoot;
    }
    # linux post-link surgery (pinned glibc interpreter/rpath via formatelf) +
    # C-lib pins; on darwin Mach-O dyld-links libSystem, so none of this applies.
    // (
      if isDarwin then
        { }
      else
        {
          glibc = pins.glibc;
          gccLib = pins.gccLib;
          formatelf = pins.formatelf;
          loader = sys.loader;
          inherit extraLibPath;
          useOpenssl = if openssl then "1" else "";
          opensslLibDir = if openssl then "${pins.openssl}/lib" else "";
          opensslIncDir = if openssl then "${pins.opensslDev}/include" else "";
          pkgConfigBin = "${pins.pkgConfig}/bin";
          pkgConfigPath = if openssl then "${pins.opensslDev}/lib/pkgconfig" else "";
        }
    )
    # caller build-time env (RUSTC_BOOTSTRAP, a build.rs data-file path, ...);
    # derivation attrs are the builder's env vars, so these reach cargo/build.rs.
    // extraEnv;
    script = if isDarwin then ./builder-darwin.sh else ./builder.sh;
  };
in
drv
// {
  # Default to x86_64-linux; a package widens meta.platforms (e.g. the formatter
  # tools shuck/nixfmt-rs run on darwin too). The darwin build path (zig cc ->
  # Mach-O, no glibc/formatelf) is new and validated on CI, not here.
  meta = {
    platforms = [ "x86_64-linux" ];
    inherit mainProgram;
  }
  // meta;
  passthru =
    (if category == null then { } else { inherit category; })
    // (if updater == null then { } else { inherit updater; })
    // (if hideFromDocs then { inherit hideFromDocs; } else { });
}
# The produced linux binaries are patchelf'd to the pinned glibc/gccLib, so the
# FHS check treats them like a kind = "patchelf" mkPackage output. Darwin Mach-O
# has no interpreter/rpath to check, so no fhs (mirrors mkPackage on darwin).
// (
  if isDarwin then
    { }
  else
    {
      fhs = {
        kind = "patchelf";
        inherit libpath mainProgram;
        ignoreMissing = "";
      };
    }
)
// (if updater == null then { } else { inherit updater; })
