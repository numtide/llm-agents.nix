# mkNpm: build an npm package from source, nixpkgs-free. Deps vendored by
# vendor/npm (a node_modules FOD, our own npmDepsHash). Installs under
# $out/lib/node_modules/<pname>, wraps each package.json "bin". Knobs: binWrappers
# override auto launchers; nativeAddons patchelf bundled *.node/*.bare to pinned glibc.
# node-gyp building an addon from source is out of scope.
scope:
{
  pname,
  version,
  src, # fetched source archive (.tar.gz, single top-level dir)
  npmDepsHash, # our node_modules FOD hash (build once with a fake hash to obtain)
  sourceRoot ? null, # subdir holding package.json (relative to the tarball top dir)
  packageLock ? null, # committed package-lock.json to inject (registry tarballs that ship none)
  omitOptional ? false, # drop optionalDependencies (cross-platform prebuilds the package ships but does not need)
  buildScript ? "build", # `npm run <buildScript>`; "" to skip (no build step)
  # Override the auto bin launchers. Attrset { <binname> = { entry = "dist/x.js";
  # nodeFlags ? [ ]; env ? { }; pathAdd ? [ <pin> ]; }; }. entry is relative to
  # the installed package root ($out/lib/node_modules/<pname>).
  binWrappers ? null,
  nativeAddons ? false, # patchelf bundled prebuilt *.node / *.bare addons to the pinned glibc
  addonLibs ? [ ], # extra C-lib pins whose /lib joins the addon rpath
  ignoreMissing ? "", # space-separated SONAMEs a native addon may leave unresolved (fhs allowlist)
  mainProgram ? pname,
  meta ? { },
  category ? null,
  updater ? null,
}:
let
  inherit (scope)
    mkDrvSh
    npmVendor
    pins
    toolchains
    ;
  inherit (toolchains) node;
  vendor = npmVendor {
    inherit
      src
      npmDepsHash
      sourceRoot
      packageLock
      omitOptional
      node
      ;
  };

  # native addon rpath: pinned glibc + gccLib (+ any extra C-lib pins).
  addonLibPath = builtins.concatStringsSep ":" (map (p: "${p}/lib") addonLibs);
  addonRpath =
    "${pins.glibc}/lib:${pins.gccLib}/lib" + (if addonLibPath == "" then "" else ":${addonLibPath}");

  # Render one custom bin wrapper into a shell block. $node/$dest are build-time
  # shell vars; \$PATH / \$@ stay literal so the emitted wrapper resolves them at runtime.
  renderWrapper =
    name: spec:
    let
      flags = builtins.concatStringsSep " " (spec.nodeFlags or [ ]);
      envs = spec.env or { };
      envEchos = builtins.concatStringsSep "\n" (
        map (k: ''echo 'export ${k}="${builtins.getAttr k envs}"' '') (builtins.attrNames envs)
      );
      pathAdd = spec.pathAdd or [ ];
      pathEcho =
        if pathAdd == [ ] then
          ""
        else
          ''echo "export PATH=\"${builtins.concatStringsSep ":" (map (p: "${p}/bin") pathAdd)}:\$PATH\""'';
    in
    ''
      {
        echo "#!/bin/sh"
      ${envEchos}
      ${pathEcho}
        echo "exec \"$node/bin/node\" ${flags} \"$dest/${spec.entry}\" \"\$@\""
      } > "$out/bin/${name}"
      chmod +x "$out/bin/${name}"
    '';
  customWrapperScript =
    if binWrappers == null then
      ""
    else
      builtins.concatStringsSep "\n" (
        map (n: renderWrapper n (builtins.getAttr n binWrappers)) (builtins.attrNames binWrappers)
      );

  drv = mkDrvSh {
    name = "${pname}-${version}";
    env = {
      inherit
        src
        node
        pname
        vendor
        ;
      sourceRoot = if sourceRoot == null then "" else sourceRoot;
      inherit buildScript;
      customBins = if binWrappers == null then "" else "1";
      nativeAddons = if nativeAddons then "1" else "";
      formatelf = pins.formatelf;
      inherit addonRpath customWrapperScript;
    };
    script = ./builder.sh;
  };
in
drv
// {
  # The wrapper + installed JS have no ELF of their own unless the package
  # bundles native addons, which we patchelf'd above. linux-only for now.
  meta = {
    platforms = [ "x86_64-linux" ];
    inherit mainProgram;
  }
  // meta;
  passthru =
    (if category == null then { } else { inherit category; })
    // (if updater == null then { } else { inherit updater; });
  fhs =
    if nativeAddons then
      {
        kind = "patchelf";
        libpath = addonRpath;
        inherit mainProgram ignoreMissing;
      }
    else
      {
        kind = "static";
        libpath = "";
        inherit mainProgram;
        ignoreMissing = "";
      };
}
// (if updater == null then { } else { inherit updater; })
