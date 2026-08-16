# go-bin: upstream prebuilt go tarball (go.dev/dl). version + per-system hash
# from ./hashes.json, platform token from systems.nix.
# go's own binaries are dynamic ELFs, so patchelf every one to the pinned glibc
# (a CGO_ENABLED=0 build output is static and needs no patching).
scope:
let
  inherit (scope)
    fetchurl
    mkDrvSh
    systems
    system
    pins
    ;
  sys = systems.${system};
  data = builtins.fromJSON (builtins.readFile ./hashes.json);

  inherit (data) version;
  tarball = fetchurl {
    url = "https://go.dev/dl/go${version}.${sys.go.platform}.tar.gz";
    hash = data.hashes.${system};
  };
in
mkDrvSh {
  name = "go-${version}";
  env = {
    inherit tarball;
    glibc = pins.glibc;
    gccLib = pins.gccLib;
    formatelf = pins.formatelf;
    loader = sys.loader;
  };
  script = ''
    tar -xzf "$tarball"
    cp -r go "$out"
    chmod -R u+w "$out"

    # patchelf every dynamic ELF in the toolchain (go/gofmt + pkg/tool/*).
    for f in $(find "$out" -type f); do
      [ "$(head -c4 "$f" | od -An -tx1 | tr -d ' \n')" = "7f454c46" ] || continue
      if "$formatelf/bin/formatelf" --print-interpreter "$f" >/dev/null 2>&1; then
        "$formatelf/bin/formatelf" --set-interpreter "$glibc/lib/$loader" --force-rpath --set-rpath "$glibc/lib:$gccLib/lib" "$f" || true
      fi
    done

    "$out/bin/go" version > "$out/go-version.txt"
  '';
}
