# Tripwire: forbid GHC/Haskell in the build entirely. Nothing here should need a
# Haskell compiler - shellcheck (the only culprit) is gone now that we lint shell
# with shuck (Rust) and writeShellApplication's shellcheck check is off (see
# no-shellcheck-wrappers.nix). This overlay makes any *future* attempt to pull
# GHC fail loudly at eval instead of silently dragging the whole Haskell closure
# back in.
#
# throw is lazy: these only fire when something actually forces the attribute, so
# normal eval is unaffected. If a new package needs Haskell, this throws with a
# pointer instead of quietly regressing eval time.
#
# Scope note: we can only ban `ghc` (the top-level compiler) + shellcheck. We do
# NOT ban `haskell` / `haskellPackages` / `pandoc`: nixpkgs uses
# `pandoc.compiler.bootstrapAvailable` (which forces haskellPackages) as a lazy
# feature-flag inside unrelated C deps - e.g. nuspell manpages, pulled
# transitively by webkitgtk -> our Tauri desktop apps (handy, gitbutler, hunk,
# ...). Banning those throws on the probe and breaks ~11 packages' eval. Those
# apps genuinely have GHC in their *build* closure (substituted from cache); this
# overlay is about keeping GHC out of OUR eval + wrapper builds, which is exactly
# shellcheck + a stray `pkgs.ghc`.
_final: _prev:
let
  banned =
    name:
    throw "${name} is disabled in llm-agents.nix (overlays/no-ghc.nix): don't pull GHC/Haskell as a build tool. Lint shell with shuck (Rust); if you truly need it, remove this overlay deliberately.";
in
{
  ghc = banned "ghc";
  shellcheck = banned "shellcheck";
  shellcheck-minimal = banned "shellcheck-minimal";
}
