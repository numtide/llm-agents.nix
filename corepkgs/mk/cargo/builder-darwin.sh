#!/bin/sh
# mkCargo darwin builder. Mach-O binaries dyld-resolve libSystem, so unlike the
# linux path there's no pinned-glibc interpreter/rpath surgery and no formatelf -
# zig cc just targets macos. Env: see mk/cargo/default.nix (darwin branch).
# shellcheck disable=SC2154,SC2164,SC2086 # env vars; set -eu aborts on cd; splits intentional
export HOME="$NIX_BUILD_TOP"
export CARGO_HOME="$NIX_BUILD_TOP/.cargo"
export ZIG_GLOBAL_CACHE_DIR="$NIX_BUILD_TOP/zig-cache"
export PATH="$rust/bin:$zig/bin:$PATH"

# zig cc wrapper: force the macos target (cc-crate build scripts pass their own
# --target/-m64, which clash; drop them). No post-link patch - dyld handles it.
cat >"$NIX_BUILD_TOP/zcc" <<EOF
#!/bin/sh
filtered=
for a in "\$@"; do
  case "\$a" in
    --target=*|-m64|-m32) continue ;;
  esac
  filtered="\$filtered \$a"
done
exec "$zig/bin/zig" cc -target $gnuTarget \$filtered
EOF
chmod +x "$NIX_BUILD_TOP/zcc"
export CC="$NIX_BUILD_TOP/zcc"

# cc-crate archives .o into .a with ar/ranlib; provide zig's llvm-ar/ranlib.
for t in ar ranlib; do
  {
    echo "#!/bin/sh"
    echo "exec \"$zig/bin/zig\" $t \"\$@\""
  } >"$NIX_BUILD_TOP/$t"
  chmod +x "$NIX_BUILD_TOP/$t"
done
export AR="$NIX_BUILD_TOP/ar"
export PATH="$NIX_BUILD_TOP:$PATH"

tar -xzf "$src"
cd "$(tar -tzf "$src" | head -1 | cut -d/ -f1)"
[ -n "$sourceRoot" ] && cd "$sourceRoot"

for p in $patchFiles; do
  patch -p1 <"$p"
done

cp "$cargoLockFile" Cargo.lock
chmod u+w Cargo.lock

mkdir -p .cargo
cat >.cargo/config.toml <<EOF
[source.crates-io]
replace-with = "vendored"
[source.vendored]
directory = "$vendor"
$gitConfig
[target.$rustGnu]
linker = "$NIX_BUILD_TOP/zcc"
EOF

cargo build --release --offline $buildFlags

mkdir -p "$out/bin"
for b in $installBins; do
  cp "target/release/$b" "$out/bin/$b"
done
