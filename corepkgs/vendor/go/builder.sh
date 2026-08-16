#!/bin/sh
# go-vendor FOD. Env: $src, $sourceRoot, $go. mkDrvSh puts busybox on PATH and
# runs us under `set -eu`. Output tree at $out.
# shellcheck disable=SC2154,SC2164 # src/sourceRoot/go/out are build-env vars; set -eu (prelude) aborts on cd failure
export PATH="$go/bin:$PATH"

export HOME="$NIX_BUILD_TOP"
export GOPATH="$NIX_BUILD_TOP/gopath"
export GOMODCACHE="$GOPATH/pkg/mod"
export GOCACHE="$NIX_BUILD_TOP/gocache"
export GOTOOLCHAIN=local
export GOFLAGS=-mod=mod

tar -xzf "$src"
cd "$(tar -tzf "$src" | head -1 | cut -d/ -f1)"
[ -n "$sourceRoot" ] && cd "$sourceRoot"

go mod vendor
cp -r vendor "$out"
