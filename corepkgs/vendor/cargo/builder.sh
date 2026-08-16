#!/bin/sh
# cargo-vendor builder. Env: $manifest (crates.io lines), $gitManifest (git-dep
# lines). $out and $NIX_BUILD_TOP come from the sandbox.
# shellcheck disable=SC2154  # manifest/gitManifest/out are build-env vars
mkdir -p "$out"
printf '%s\n' "$manifest" | while read -r name version sha crate; do
  [ -n "$name" ] || continue
  # each .crate untars to $out/<name>-<version>/
  tar -xzf "$crate" -C "$out"
  printf '{"files":{},"package":"%s"}' "$sha" >"$out/$name-$version/.cargo-checksum.json"
done
# git deps: the archive untars to a single <repo>-<rev>/ top dir; move it to
# $out/<crate>/ and give it the git-source null-package checksum.
printf '%s\n' "$gitManifest" | while read -r crate archive; do
  [ -n "$crate" ] || continue
  rm -rf "$NIX_BUILD_TOP/gx" && mkdir -p "$NIX_BUILD_TOP/gx"
  tar -xzf "$archive" -C "$NIX_BUILD_TOP/gx"
  mv "$NIX_BUILD_TOP/gx"/* "$out/$crate"
  printf '{"files":{},"package":null}' >"$out/$crate/.cargo-checksum.json"
done
