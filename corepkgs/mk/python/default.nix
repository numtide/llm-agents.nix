# mkPython: build a Python application from source, nixpkgs-free. Deps vendored
# by vendor/python (a site-packages FOD from `pip install --target`, our own
# hash). Installs the site tree under $out/lib/pysite and wraps each console entry
# point as a launcher running the toolchain python with that tree on PYTHONPATH.
# Pure-python + manylinux-wheel deps only; sdist-compiled C deps out of scope.
scope:
{
  pname,
  version,
  src, # fetched source archive (.tar.gz, single top-level dir)
  pythonDepsHash, # our site-packages FOD hash (build once with a fake hash to obtain)
  entrypoints, # { <binname> = "module:attr"; } from pyproject [project.scripts]
  sourceRoot ? null, # subdir holding pyproject.toml (relative to the tarball top dir)
  postPatch ? "", # shell run in the source before `pip install` (e.g. a version fixup)
  mainProgram ? pname,
  meta ? { },
  category ? null,
  updater ? null,
}:
let
  inherit (scope)
    mkDrvSh
    pythonVendor
    pins
    toolchains
    ;
  inherit (toolchains) python;
  vendor = pythonVendor {
    inherit
      src
      pythonDepsHash
      sourceRoot
      postPatch
      python
      ;
  };
  # the manylinux external libs wheels may link (mirrors toolchains/python.nix);
  # the fhs check resolves each vendored wheel .so against this set.
  manylinux = [
    pins.glibc
    pins.gccLib
    pins.zlib
    pins.libffi
    pins.expat
    pins.ncurses
    pins.openssl
    pins.bzip2
    pins.xz
  ];
  ldpath = builtins.concatStringsSep ":" (map (p: "${p}/lib") manylinux);

  # one launcher per console_scripts entry: name = "module:attr".
  renderWrapper =
    name: spec:
    let
      m = builtins.match "([^:]+):(.+)" spec;
      mod = builtins.elemAt m 0;
      attr = builtins.elemAt m 1;
    in
    ''
      {
        echo "#!$python/py/sh"
        echo "export PYTHONPATH=\"$out/lib/pysite\''${PYTHONPATH:+:\$PYTHONPATH}\""
        echo "exec \"$python/bin/python3\" -c 'import sys; from ${mod} import ${attr}; sys.exit(${attr}())' \"\$@\""
      } > "$out/bin/${name}"
      chmod +x "$out/bin/${name}"
    '';
  wrapperScript = builtins.concatStringsSep "\n" (
    map (n: renderWrapper n (builtins.getAttr n entrypoints)) (builtins.attrNames entrypoints)
  );

  drv = mkDrvSh {
    name = "${pname}-${version}";
    env = {
      inherit vendor python;
      inherit wrapperScript; # per-entrypoint launchers, eval'd in the builder
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
  # vendored wheels' .so's carry no rpath (they rely on the toolchain's
  # LD_LIBRARY_PATH); the fhs check resolves their NEEDED against the manylinux
  # set, so a wheel needing a lib outside it fails loudly.
  fhs = {
    kind = "patchelf";
    libpath = ldpath;
    inherit mainProgram;
    ignoreMissing = "";
  };
}
// (if updater == null then { } else { inherit updater; })
