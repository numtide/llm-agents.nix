#!/usr/bin/env bash
# Regenerate the rehydrated pins backend data (closure.json + manifest.json +
# srcs/). Run from anywhere; writes next to this script. Re-run after a nixpkgs
# or pin bump. See ../rehydrate.nix and ../REHYDRATE-NOTES.md for the why.
#
# What it does: take the same pins as pins/pkgs.nix (minus formatelf, whose rust
# closure we don't serialize), serialize each pin's full from-source .drv graph
# with `nix derivation show -r`, and inline every non-URL-fetchable inputSrc
# (patches, setup hooks) so the graph rebuilds with zero cache dependency.
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo=$(cd "$here/../../.." && pwd)
cd "$repo"

# Pin to the flake's own nixpkgs rev so the serialized graph matches pkgs.nix.
rev=$(jq -r '.nodes.nixpkgs.locked.rev' flake.lock)
np="github:NixOS/nixpkgs/$rev"

# pin name -> { drv = "<store-name>.drv"; output = "out"|"dev"|"lib"|... }
nix eval --impure --json --expr "
  let pkgs = import (builtins.getFlake \"$np\") { system = \"x86_64-linux\"; };
      pins = removeAttrs (import $repo/corepkgs/pins/pkgs.nix pkgs) [ \"formatelf\" ];
  in builtins.mapAttrs (_: p: { drv = baseNameOf p.drvPath; output = p.outputName; }) pins
" | jq -S '.' >"$here/manifest.json"

# The combined pin .drv closure, keyed by store-name (no /nix/store prefix).
mapfile -t drvpaths < <(nix eval --impure --json --expr "
  let pkgs = import (builtins.getFlake \"$np\") { system = \"x86_64-linux\"; };
      pins = removeAttrs (import $repo/corepkgs/pins/pkgs.nix pkgs) [ \"formatelf\" ];
  in map (p: p.drvPath) (builtins.attrValues pins)
" | jq -r '.[]')
nix derivation show -r "${drvpaths[@]}" | jq -c '.' >"$here/closure.json"

# Inline every inputSrc by content. Preserve the executable bit: it is part of
# the NAR hash, so builtins.path only reproduces the store path when it matches.
rm -rf "$here/srcs" && mkdir -p "$here/srcs"
mapfile -t srcs < <(jq -r '[.derivations[].inputs.srcs[]?] | unique[]' "$here/closure.json")
for s in "${srcs[@]}"; do
  cp -r --preserve=mode "/nix/store/$s" "$here/srcs/$s"
done
chmod -R u+w "$here/srcs"

echo "wrote closure.json ($(jq '.derivations | length' "$here/closure.json") nodes), manifest.json ($(jq 'length' "$here/manifest.json") pins), srcs/ (${#srcs[@]} files)"
