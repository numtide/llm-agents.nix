# zig-bin: upstream prebuilt zig tarball. No glibc pin (uniquely): the zig binary
# is truly static and `zig cc` is a self-contained C/C++ compiler + linker + libc.
# version + per-system hash from ./hashes.json, platform token from systems.nix.
# darwin has no busybox seed, so the cc/c++ wrappers use the system /bin/sh.
scope:
let
  inherit (scope)
    fetchurl
    mkDrvSh
    seed
    systems
    system
    ;
  sys = systems.${system};
  isDarwin = builtins.match ".*-darwin" system != null;
  data = builtins.fromJSON (builtins.readFile ./hashes.json);

  inherit (data) version;
  plat = sys.zig.platform; # e.g. x86_64-linux / aarch64-macos
  muslTarget = "${plat}-musl"; # zig cc smoke-test target (linux static)
  tarball = fetchurl {
    url = "https://ziglang.org/download/${version}/zig-${plat}-${version}.tar.xz";
    hash = data.hashes.${system};
  };
in
mkDrvSh {
  name = "zig-${version}";
  env = {
    inherit tarball;
  }
  // (if isDarwin then { } else { busybox = seed.busybox; });
  script = ''
    tar -xf "$tarball"
    cp -r "zig-${plat}-${version}" "$out"
    chmod -R u+w "$out"
    mkdir -p "$out/bin"
    ln -s ../zig "$out/bin/zig"

    ${
      if isDarwin then
        ''sh="/bin/sh"''
      else
        ''
          ln -s "$busybox" "$out/bin/sh"
          sh="$out/bin/sh"''
    }
    for tool in cc c++; do
      {
        echo "#!$sh"
        echo "exec \"$out/zig\" $tool \"\$@\""
      } > "$out/bin/$tool"
      chmod +x "$out/bin/$tool"
    done

    export ZIG_GLOBAL_CACHE_DIR="$NIX_BUILD_TOP/zig-cache"
    ${
      if isDarwin then
        ''"$out/bin/zig" version > "$out/selftest.txt"''
      else
        ''
          printf '#include <stdio.h>\nint main(){printf("zig cc ok\\n");return 0;}\n' > t.c
          "$out/bin/cc" -target ${muslTarget} -o t.out t.c
          ./t.out > "$out/selftest.txt"
          "$out/bin/zig" version >> "$out/selftest.txt"''
    }
  '';
}
