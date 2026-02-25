# shellcheck shell=bash
# Setup hook that relaxes go.mod version constraints to match the Go toolchain
# used by the build. This prevents "go.mod requires go >= X.Y.Z" errors when
# upstream pins a newer patch version than nixpkgs ships.

unpinGoModVersion() {
  if [[ ! -f go.mod ]]; then
    return
  fi

  local goVersion
  goVersion="$(go env GOVERSION)"
  # go env GOVERSION returns e.g. "go1.25.5" – strip the "go" prefix
  goVersion="${goVersion#go}"

  echo "unpinGoModVersionHook: setting go.mod go directive to $goVersion"
  sed -i "s/^go .*/go $goVersion/" go.mod

  if grep -q '^toolchain ' go.mod; then
    echo "unpinGoModVersionHook: removing toolchain directive from go.mod"
    sed -i '/^toolchain /d' go.mod
  fi
}

postPatchHooks+=(unpinGoModVersion)
