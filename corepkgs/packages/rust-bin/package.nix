# rust-bin: upstream prebuilt rust components (rustc + cargo + rust-std). version
# + per-system component hashes from ./hashes.json; target triple (`rust.gnu`,
# shared with mkCargo) in systems.nix.
# linux: merge into one prefix + formatelf every ELF (pinned glibc interpreter +
# rpath; .so's get their stale DT_RUNPATH stripped) + a musl std for zig-cc
# static builds. darwin: extract natively - Mach-O binaries dyld-resolve
# libSystem, so no interpreter/rpath surgery, and no musl std.
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
  isDarwin = builtins.match ".*-darwin" system != null;
  data = builtins.fromJSON (builtins.readFile ./hashes.json);
  h = data.hashes.${system};

  inherit (data) version;
  triple = sys.rust.gnu; # gnu triple on linux, apple-darwin triple on darwin
  comp =
    name: hash:
    fetchurl {
      url = "https://static.rust-lang.org/dist/${name}-${version}-${triple}.tar.gz";
      inherit hash;
    };
in
mkDrvSh {
  name = "rust-${version}";
  env = {
    rustc = comp "rustc" h.rustc;
    cargo = comp "cargo" h.cargo;
    ruststd = comp "rust-std" h.std;
  }
  // (
    if isDarwin then
      { }
    else
      {
        muslStd = fetchurl {
          url = "https://static.rust-lang.org/dist/rust-std-${version}-${sys.rust.musl}.tar.gz";
          hash = h.muslStd;
        };
        glibc = pins.glibc;
        formatelf = pins.formatelf;
        gccLib = pins.gccLib;
        zlib = pins.zlib;
        zstd = pins.zstd;
      }
  );
  script =
    if isDarwin then
      ''
        tar -xzf "$rustc"
        tar -xzf "$cargo"
        tar -xzf "$ruststd"

        mkdir -p "$out"
        cp -r "rustc-${version}-${triple}/rustc/." "$out/"
        cp -r "cargo-${version}-${triple}/cargo/." "$out/"
        cp -r "rust-std-${version}-${triple}/rust-std-${triple}/." "$out/"
        chmod -R u+w "$out"

        # native Mach-O: dyld resolves libSystem, no interpreter/rpath surgery.
        "$out/bin/rustc" --version > "$out/rustc-version.txt"
        "$out/bin/cargo" --version > "$out/cargo-version.txt"
      ''
    else
      ''
        tar -xzf "$rustc"
        tar -xzf "$cargo"
        tar -xzf "$ruststd"

        mkdir -p "$out"
        cp -r "rustc-${version}-${triple}/rustc/." "$out/"
        cp -r "cargo-${version}-${triple}/cargo/." "$out/"
        cp -r "rust-std-${version}-${triple}/rust-std-${triple}/." "$out/"
        tar -xzf "$muslStd"
        cp -r "rust-std-${version}-${sys.rust.musl}/rust-std-${sys.rust.musl}/." "$out/"
        chmod -R u+w "$out"

        RPATH="$out/lib:$glibc/lib:$gccLib/lib:$zlib/lib:$zstd/lib"
        for exe in "$out/bin/rustc" "$out/bin/cargo"; do
          "$formatelf/bin/formatelf" --set-interpreter "$glibc/lib/${sys.loader}" --force-rpath --set-rpath "$RPATH" "$exe"
        done
        # real ELF objects only: some *.so* (musl self-contained stubs) are linker
        # scripts, which formatelf rejects rather than ignores.
        for so in $(find "$out/lib" -name '*.so*' -type f); do
          [ "$(head -c4 "$so" | od -An -tx1 | tr -d ' \n')" = "7f454c46" ] || continue
          "$formatelf/bin/formatelf" --remove-rpath "$so" || true
        done

        "$out/bin/rustc" --version > "$out/rustc-version.txt"
        "$out/bin/cargo" --version > "$out/cargo-version.txt"
      '';
}
