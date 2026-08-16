#!/bin/sh
# mkGo builder. mkDrvSh puts busybox on PATH and runs us under `set -eu`.
# Env: see mk/go/default.nix.
# shellcheck disable=SC2154,SC2164,SC2086 # env vars; set -eu aborts on cd; $pairs/$ldf split on purpose
export HOME="$NIX_BUILD_TOP"
export GOPATH="$NIX_BUILD_TOP/gopath"
export GOCACHE="$NIX_BUILD_TOP/gocache"
export GOTOOLCHAIN=local
export PATH="$go/bin:$PATH"

if [ -n "$useCgo" ]; then
  # cgo: compile C via zig cc; provide zig's llvm ar/ranlib + pkg-config
  # for `#cgo pkg-config:` directives. Dynamic output, patchelf'd below.
  export CGO_ENABLED=1
  cat >"$NIX_BUILD_TOP/zcc" <<EOF
#!/bin/sh
filtered=
for a in "\$@"; do
  case "\$a" in --target=*|-m64|-m32) continue ;; esac
  filtered="\$filtered \$a"
done
exec "$zig/bin/zig" cc -target $gnuTarget \$filtered
EOF
  chmod +x "$NIX_BUILD_TOP/zcc"
  export CC="$NIX_BUILD_TOP/zcc"
  for t in ar ranlib; do
    {
      echo "#!/bin/sh"
      echo "exec \"$zig/bin/zig\" $t \"\$@\""
    } >"$NIX_BUILD_TOP/$t"
    chmod +x "$NIX_BUILD_TOP/$t"
  done
  export AR="$NIX_BUILD_TOP/ar"
  export PATH="$NIX_BUILD_TOP:$pkgConfigBin:$PATH"
  [ -n "$pkgConfigPath" ] && export PKG_CONFIG_PATH="$pkgConfigPath"
else
  export CGO_ENABLED=0
fi

tar -xzf "$src"
cd "$(tar -tzf "$src" | head -1 | cut -d/ -f1)"
[ -n "$sourceRoot" ] && cd "$sourceRoot"

export GOFLAGS=-mod=vendor GOPROXY=off GOSUMDB=off
if [ -n "$vendor" ]; then
  # drop in the vendored modules (the FOD is read-only, so copy writable)
  cp -r "$vendor" vendor
  chmod -R u+w vendor
fi
# else: vendorHash = null - the source commits its own vendor/ dir in-tree.

mkdir -p "$out/bin"
ldf=""
[ -n "$ldflags" ] && ldf="-ldflags=$ldflags"
tagf=""
[ -n "$tags" ] && tagf="-tags=$tags"
for pair in $pairs; do
  pkg="${pair%%:*}"
  bin="${pair##*:}"
  # quote $ldf/$tagf: they hold space-separated ldflags as ONE go arg
  go build ${ldf:+"$ldf"} ${tagf:+"$tagf"} -o "$out/bin/$bin" "./$pkg"
  # cgo output is a dynamic ELF: point it at the pinned glibc + set rpath.
  if [ -n "$useCgo" ]; then
    "$formatelf/bin/formatelf" --set-interpreter "$glibc/lib/$loader" --force-rpath --set-rpath "$cgoLibpath" "$out/bin/$bin"
  fi
done
