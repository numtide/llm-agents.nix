# mkPackage: fetch a prebuilt release artifact, unpack, make it runnable, wrap.
#
# kind:
#   "patchelf" - dynamic ELF: rewrite interpreter/rpath (via formatelf) to the
#                pinned glibc (+ extra libs).
#   "loader"   - bun --compile binary: ELF rewrite segfaults its appended JS
#                payload, so leave it byte-intact and invoke the pinned loader
#                through a wrapper instead.
scope:
{
  pname,
  # Source: either literal src+version, OR the repo's shared hashesFile
  # (packages/<name>/hashes.json: {version, hashes.<system>}) + urlTemplate
  # (interpolated with {version}) so nothing duplicates what nix-update bumps.
  version ? null,
  src ? null,
  hashesFile ? null,
  urlTemplate ? null,
  # { <system> = "<platform-token>"; } multi-platform map (mirrors
  # fetch/platform-source.nix). Fills urlTemplate's {platform} per system; its
  # key set is meta.platforms, so the flake gates unsupported systems before src
  # is forced. null = single-platform (platform baked into urlTemplate).
  platforms ? null,
  unpack ? "none", # "none" | "zip" | "tar" | "auto" (infer from the resolved URL extension)
  binary ? pname, # path to the main binary after unpack (single-file mode)
  installDir ? null, # dir to copy wholesale (dir-install mode)
  mainProgram ? pname, # name of the wrapper in $out/bin
  entrypoint ? null, # path to the real binary inside the tree (dir-install with a nested launcher, e.g. "bin/junie"); defaults to mainProgram
  kind ? "patchelf", # "patchelf" | "loader"
  libs ? [ ], # extra store paths whose /lib joins the rpath/library-path
  runtimeBins ? [ ], # [{ name; src; }] prebuilt binaries bundled onto PATH
  runtimePkgs ? [ ], # pinned store paths whose /bin joins PATH
  ignoreMissing ? [ ], # SONAMEs allowed to stay unresolved (optional deps of a bundled JRE etc.)
  setEnv ? { }, # { VAR = "val"; } exported in the wrapper before exec
  extraArgs ? [ ], # flags appended to the wrapped exec, before "$@" (e.g. --no-auto-update)
  aliases ? [ ], # extra $out/bin/<name> wrappers, each exec'd with argv0=<name>
  # Package metadata carried onto the bare derivation so the flake's
  # meta-completeness / README / updater machinery treat it like any package.
  category ? null, # passthru.category
  updater ? null, # passthru.updater (declarative config from mkUpdater)
  meta ? { }, # merged into output meta
}:
let
  inherit (scope)
    seed
    mkDrvNu
    systems
    fetchurl
    interpolate
    system
    pins
    ;
  sys = systems.${system};
  isDarwin = builtins.match ".*-darwin" system != null;

  hashData = if hashesFile == null then null else builtins.fromJSON (builtins.readFile hashesFile);
  resolvedVersion = if hashData == null then version else hashData.version;
  # A platforms entry is a string (shorthand for the {platform} token) or an
  # attrset of arbitrary URL vars (e.g. { os = "linux"; cpu = "x86_64"; } for a
  # "{os}/{cpu}" template) - same contract as fetch/platform-source.nix.
  platformVars =
    if platforms == null then
      { }
    else
      let
        entry = platforms.${system};
      in
      if builtins.isAttrs entry then entry else { platform = entry; };
  resolvedUrl =
    if urlTemplate == null then
      null
    else
      interpolate urlTemplate ({ version = resolvedVersion; } // platformVars);
  resolvedSrc =
    if src != null then
      src
    else
      fetchurl {
        url = resolvedUrl;
        hash = hashData.hashes.${system} or hashData.${system};
      };

  # unpack = "auto" infers the archive kind from the URL extension, so one
  # package.nix can serve platforms with differing assets (darwin .zip vs linux
  # .tar.gz). Explicit "none"/"tar"/"zip" always win.
  inferUnpack =
    u:
    if u != null && builtins.match ".*\\.zip" u != null then
      "zip"
    else if u != null && builtins.match ".*(\\.tar\\.gz|\\.tgz|\\.tar\\.xz|\\.tar)" u != null then
      "tar"
    else
      "none";
  resolvedUnpack = if unpack == "auto" then inferUnpack resolvedUrl else unpack;

  # Darwin Mach-O links system libSystem via dyld: no rpath rewriting, no loader,
  # no glibc/formatelf pins. libpath is Linux-only.
  libpath =
    if isDarwin then
      ""
    else
      builtins.concatStringsSep ":" (
        map (p: "${p}/lib") (
          [
            pins.glibc
            pins.gccLib
          ]
          ++ libs
        )
      );
  drv = mkDrvNu {
    name = "${pname}-${resolvedVersion}";
    env = {
      src = resolvedSrc;
      inherit
        pname
        mainProgram
        kind
        ;
      os = if isDarwin then "darwin" else "linux";
      entry = if entrypoint == null then mainProgram else entrypoint;
      busybox = if isDarwin then "" else seed.busybox;
      glibc = if isDarwin then "" else pins.glibc;
      formatelf = if isDarwin then "" else pins.formatelf;
      inherit libpath;
      loader = if isDarwin then "" else "${pins.glibc}/lib/${sys.loader}";
      unpackKind = resolvedUnpack;
      binaryPath = binary;
      installDir = if installDir == null then "" else installDir;
      # __structuredAttrs: pass real structured data, not string-munged env vars.
      inherit runtimeBins; # [ { name; src; } ]
      inherit setEnv; # { VAR = "val"; }
      inherit extraArgs aliases; # wrapper flags + argv0-aliased wrappers
      runtimePath = builtins.concatStringsSep ":" (map (p: "${p}/bin") runtimePkgs);
    };
    # Nushell builder (see drv-nu.nix): `$attrs` = JSON attrs record, `$out` = output
    # path, busybox applets are external `^cmd`s on PATH.
    script = ''
      mkdir $"($out)/bin" $"($out)/libexec"

      let formatelf = $"($attrs.formatelf)/bin/formatelf"

      # patch only dynamic binaries (those with an interpreter)
      let fixelf = {|f|
        if ((^$formatelf --print-interpreter $f | complete).exit_code == 0) {
          ^$formatelf --set-interpreter $attrs.loader --set-rpath $attrs.libpath $f
        }
      }

      if $attrs.unpackKind == "zip" {
        ^unzip -q $attrs.src
      } else if $attrs.unpackKind == "tar" {
        ^tar -xf $attrs.src
      }

      mut bindir = $"($out)/libexec"
      if ($attrs.installDir | is-not-empty) {
        # dir-install: copy the whole tree; entrypoint is one file inside it
        $bindir = $"($out)/libexec/($attrs.pname)"
        mkdir $bindir
        ^cp -r $"($attrs.installDir)/." $bindir
      } else {
        if $attrs.unpackKind == "none" {
          ^cp $attrs.src $"($bindir)/($attrs.entry)"
        } else {
          ^cp $attrs.binaryPath $"($bindir)/($attrs.entry)"
        }
      }
      ^chmod -R u+w $bindir
      ^chmod 0755 $"($bindir)/($attrs.entry)"

      # bundle prebuilt binaries onto PATH (e.g. a vendored ripgrep)
      for b in $attrs.runtimeBins {
        ^cp $b.src $"($out)/libexec/($b.name)"
        ^chmod 0755 $"($out)/libexec/($b.name)"
        if $attrs.os == "linux" { do $fixelf $"($out)/libexec/($b.name)" }
      }

      # ELF patching is Linux-only; Mach-O binaries need no rpath rewriting.
      if $attrs.kind == "patchelf" and $attrs.os == "linux" {
        if ($attrs.installDir | is-not-empty) {
          # dir-install: patch every ELF - executables get loader + rpath, shared
          # libs just rpath. rpath = every in-tree dir holding a .so (so intra-tree
          # deps like a JRE's libjli.so resolve) then the pinned libs.
          let treelibs = (
            ^find $bindir -name '*.so*' -type f
            | lines
            | each {|so| $"($so | path dirname):" }
            | uniq
            | str join ""
          )
          let rp = $treelibs + $attrs.libpath
          for f in (^find $bindir -type f | lines) {
            let magic = (^head -c4 $f | ^od -An -tx1 | str replace --all --regex '\s' "")
            if $magic == "7f454c46" {
              if ((^$formatelf --print-interpreter $f | complete).exit_code == 0) {
                ^$formatelf --set-interpreter $attrs.loader --set-rpath $rp $f | complete | ignore
              } else {
                ^$formatelf --set-rpath $rp $f | complete | ignore
              }
            }
          }
        } else {
          do $fixelf $"($bindir)/($attrs.entry)"
        }
      }

      # wrapper PATH: bundled bins ($out/libexec + bindir) then pinned tools.
      # let (not mut): nushell closures can't capture mutable variables.
      let wrapperpath = (if ($attrs.runtimePath | is-not-empty) { $"($out)/libexec:($bindir):($attrs.runtimePath)" } else { $"($out)/libexec:($bindir)" })

      # wrapper interpreter: Linux uses the bundled busybox sh (nixpkgs-free),
      # darwin the system /bin/sh (always present, like libSystem).
      let sh = (
        if $attrs.os == "linux" {
          ^ln -s $attrs.busybox $"($out)/libexec/sh"
          $"($out)/libexec/sh"
        } else { "/bin/sh" }
      )

      # immutable alias of the (mut) bindir so the closure can capture it
      let wbindir = $bindir

      # extra flags appended to the wrapped binary before "$@" (e.g. --no-auto-update)
      let flags = ($attrs.extraArgs | each {|a| $'"($a)"' } | str join " ")

      # one wrapper: a /bin/sh script that sets PATH/env then exec's the binary.
      # argv0 lets aliases (e.g. `agent`) make the binary see a different name;
      # `exec -a` works in both busybox ash and macOS sh.
      let mkwrapper = {|wname: string, argv0: string|
        mut lines = [ $"#!($sh)" ]
        $lines = ($lines | append $'export PATH="($wrapperpath)''${PATH:+:$PATH}"')
        if ($attrs.setEnv | is-not-empty) {
          for e in ($attrs.setEnv | transpose key value) {
            $lines = ($lines | append $'export ($e.key)=($e.value)')
          }
        }
        let tail = (if ($flags | is-empty) { ' "$@"' } else { $' ($flags) "$@"' })
        # loader-invoke is Linux-only (bun --compile); darwin execs directly.
        if $attrs.kind == "loader" and $attrs.os == "linux" {
          $lines = ($lines | append $'exec -a "($argv0)" "($attrs.loader)" --library-path "($attrs.libpath)" "($wbindir)/($attrs.entry)"($tail)')
        } else {
          $lines = ($lines | append $'exec -a "($argv0)" "($wbindir)/($attrs.entry)"($tail)')
        }
        (($lines | str join "\n") + "\n") | save --raw --force $"($out)/bin/($wname)"
        ^chmod +x $"($out)/bin/($wname)"
      }

      do $mkwrapper $attrs.mainProgram $attrs.mainProgram
      for a in $attrs.aliases { do $mkwrapper $a $a }
    '';
  };
in
drv
// {
  # meta for the flake's availableOn gating + checks. platforms is the full
  # supported set (map keys) so an unsupported system filters out before src is
  # forced; single-platform builds report [ system ]. Reading .meta never forces
  # the derivation (lazy `//`). Caller's meta merges on top of these defaults.
  meta = {
    platforms = if platforms == null then [ system ] else builtins.attrNames platforms;
    inherit mainProgram;
  }
  // meta;
  # passthru: category (README + meta-completeness) + declarative updater config.
  # `updater` is also lifted top-level: the flake's withUpdateScript keys on
  # `pkg ? updater`.
  passthru =
    (if category == null then { } else { inherit category; })
    // (if updater == null then { } else { inherit updater; });
}
// (if updater == null then { } else { inherit updater; })
// {
  fhs = {
    inherit kind libpath mainProgram;
    ignoreMissing = builtins.concatStringsSep " " ignoreMissing;
  };
}
