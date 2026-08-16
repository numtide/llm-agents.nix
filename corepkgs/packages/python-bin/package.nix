# python-bin: upstream relocatable prebuilt CPython (astral
# python-build-standalone). version + release tag + hash from ./hashes.json.
# Patchelf the interpreter to the pinned glibc; the wrapper sets LD_LIBRARY_PATH
# to the manylinux external-library set. x86_64-linux only (the manylinux lib
# pins are x86_64).
scope:
let
  inherit (scope)
    fetchurl
    mkDrvSh
    seed
    systems
    system
    pins
    ;
  sys = systems.${system};
  data = builtins.fromJSON (builtins.readFile ./hashes.json);

  inherit (data) version tag;
  tarball = fetchurl {
    url = "https://github.com/astral-sh/python-build-standalone/releases/download/${tag}/cpython-${version}%2B${tag}-x86_64-unknown-linux-gnu-install_only.tar.gz";
    inherit (data) hash;
    name = "cpython-${version}.tar.gz";
  };

  # manylinux external libs that wheels may link against
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
in
mkDrvSh {
  name = "python-${version}";
  env = {
    inherit tarball ldpath;
    busybox = seed.busybox;
    glibc = pins.glibc;
    formatelf = pins.formatelf;
  };
  script = ''
    tar -xzf "$tarball" # -> python/
    mkdir -p "$out"
    cp -r python "$out/py"
    chmod -R u+w "$out/py"

    # interpreter: pinned loader + DT_RPATH (own lib for libpython/libtcl, plus
    # glibc). --force-rpath is transitive, so the stdlib .so's resolve too.
    "$formatelf/bin/formatelf" \
      --set-interpreter "$glibc/lib/${sys.loader}" \
      --force-rpath --set-rpath "$out/py/lib:$ldpath" \
      "$out/py/bin/python3.12"

    mkdir -p "$out/bin"
    ln -s "$busybox" "$out/py/sh"
    for name in python python3; do
      {
        echo "#!$out/py/sh"
        echo "export LD_LIBRARY_PATH=\"$ldpath\''${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}\""
        echo "exec \"$out/py/bin/python3.12\" \"\$@\""
      } > "$out/bin/$name"
      chmod +x "$out/bin/$name"
    done

    # smoke test: interpreter + a spread of stdlib C extensions load
    "$out/bin/python3" -c 'import ssl, ctypes, sqlite3, bz2, lzma, hashlib, zlib, curses, decimal; print("python", __import__("sys").version.split()[0], "+ stdlib C-extensions ok")' > "$out/selftest.txt"
  '';
}
