#!/bin/sh
# mkCargo builder. mkDrvSh puts busybox on PATH and runs us under `set -eu`.
# Env: see mk/cargo/default.nix. $gitConfig is the [source."..."] git-dep block.
# shellcheck disable=SC2154,SC2164 # env vars from derivation; set -eu (prelude) aborts on cd failure
# shellcheck disable=SC2086 # $buildFlags/$installBins/$patchFiles split on purpose
export HOME="$NIX_BUILD_TOP"
export CARGO_HOME="$NIX_BUILD_TOP/.cargo"
export ZIG_GLOBAL_CACHE_DIR="$NIX_BUILD_TOP/zig-cache"
export PATH="$rust/bin:$zig/bin:$PATH"

ld="$glibc/lib/$loader"
libp="$glibc/lib:$gccLib/lib"
[ -n "$extraLibPath" ] && libp="$libp:$extraLibPath"

# openssl-sys / native-tls: use the pinned openssl (headers + libs) instead
# of the vendored openssl-src (whose build.rs needs perl) or a system lib.
# pkg-config for -sys crates that probe it (openssl-sys, etc.)
export PATH="$pkgConfigBin:$PATH"
[ -n "$pkgConfigPath" ] && export PKG_CONFIG_PATH="$pkgConfigPath"
# When linking a pinned shared C lib (openssl's libcrypto.so), that lib has
# its OWN undefined glibc refs (pthread_mutex_trylock@GLIBC_2.34, ...). They
# resolve at runtime (glibc is in the rpath), so relax zig/lld's default
# --no-allow-shlib-undefined at link time.
if [ -n "$extraLibPath" ]; then
  export RUSTFLAGS="-C link-arg=-Wl,--allow-shlib-undefined${RUSTFLAGS:+ $RUSTFLAGS}"
fi
if [ -n "$useOpenssl" ]; then
  export OPENSSL_NO_VENDOR=1
  export OPENSSL_LIB_DIR="$opensslLibDir"
  export OPENSSL_INCLUDE_DIR="$opensslIncDir"
fi

# zig cc wrapper: force the glibc target (else zig falls back to musl and
# rust's gnu std can't resolve gnu_get_libc_version/mmap64), then POST-LINK
# patch each produced executable with the pinned formatelf (skip -shared:
# dylibs have no interpreter).
cat >"$NIX_BUILD_TOP/zcc" <<EOF
#!/bin/sh
# cc crate (-sys build scripts) passes its own --target=<triple> and -m64,
# which clash with our forced -target; drop them. Track -c so we only
# post-link-patch actual executables, not compiled .o objects. (nix store
# paths have no spaces, so unquoted \$filtered is safe.)
filtered=
compile=0
for a in "\$@"; do
  case "\$a" in
    --target=*|-m64|-m32) continue ;;
    -c) compile=1 ;;
  esac
  filtered="\$filtered \$a"
done
"$zig/bin/zig" cc -target $gnuTarget \$filtered || exit \$?
[ "\$compile" -eq 1 ] && exit 0
shared=0; out=""; prev=""
for a in "\$@"; do
  [ "\$a" = "-shared" ] && shared=1
  [ "\$prev" = "-o" ] && out="\$a"
  prev="\$a"
done
if [ "\$shared" -eq 0 ] && [ -n "\$out" ] && [ -f "\$out" ]; then
  "$formatelf/bin/formatelf" --set-interpreter "$ld" --force-rpath --set-rpath "$libp" "\$out" 2>/dev/null || true
fi
EOF
chmod +x "$NIX_BUILD_TOP/zcc"
export CC="$NIX_BUILD_TOP/zcc"

# cc-crate (-sys build scripts) archives compiled .o into .a with `ar` and
# `ranlib`; busybox ar cannot create archives, so provide zig's llvm-ar/
# ranlib. Put them (and zcc) on PATH so bare `ar`/`cc` invocations resolve.
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

# apply source patches (patch -p1), before the lock copy + build
for p in $patchFiles; do
  patch -p1 <"$p"
done

# Make the vendored lock authoritative: copy our Cargo.lock over the
# source's (they are usually identical; this also fixes tarballs whose
# in-tree lock is stale relative to Cargo.toml). Drop --locked since the
# lock is now ours and all deps are vendored + --offline.
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
