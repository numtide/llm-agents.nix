# bun-bin: upstream prebuilt bun binary. version + per-system hash from
# ./hashes.json, platform token from systems.nix.
#
# bun must NOT be patchelf'd: it appends its JS runtime to the ELF tail and
# recomputes that offset from the on-disk file, so any rewrite segfaults it.
# Leave it byte-intact; invoke the pinned glibc loader via a wrapper.
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

  inherit (data) version;
  plat = sys.bun.platform;
  zip = fetchurl {
    url = "https://github.com/oven-sh/bun/releases/download/bun-v${version}/bun-${plat}.zip";
    hash = data.hashes.${system};
  };
in
mkDrvSh {
  name = "bun-${version}";
  env = {
    inherit zip;
    busybox = seed.busybox;
    glibc = pins.glibc;
    gccLib = pins.gccLib;
  };
  script = ''
    mkdir -p "$out/libexec" "$out/bin"
    unzip -q "$zip"
    cp bun-${plat}/bun "$out/libexec/bun"
    chmod +x "$out/libexec/bun"

    # runtime shell: busybox symlinked as "sh"
    ln -s "$busybox" "$out/libexec/sh"
    {
      echo "#!$out/libexec/sh"
      echo "exec \"$glibc/lib/${sys.loader}\" --library-path \"$glibc/lib:$gccLib/lib\" \"$out/libexec/bun\" \"\$@\""
    } > "$out/bin/bun"
    chmod +x "$out/bin/bun"

    "$out/bin/bun" --version > "$out/version.txt"
  '';
}
