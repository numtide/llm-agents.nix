# Remove pandoc (Haskell) from the webkitgtk/Tauri apps' build closures. nuspell
# generates optional man pages with pandoc (nuspell -> enchant -> webkitgtk ->
# handy, gitbutler, kandev-desktop, ...), dragging the whole GHC + pandoc stack
# (46 drvs) into each. It has an `enableManpages` flag, so just flip it - handy's
# ghc/pandoc drvs go 46 -> 0.
#
# Cost: changes nuspell's hash, so enchant + webkitgtk + those apps rebuild from
# source once, then substitute from cache. We lose nuspell's man pages.
#
# NOT fully removable: the bun packages (aionui, backlog-md, hunk, ...) pull
# pandoc via bun2nix-hook -> yq-go's manpage step. bun2nix re-resolves yq-go
# through its own scope (pkgsBun), so a top-level `yq-go.overrideAttrs` here does
# not reach the go-modules FOD it actually builds - those keep pandoc. Banning
# pandoc outright therefore breaks ~10 bun packages' eval, so we don't.
_final: prev: {
  nuspell = prev.nuspell.override { enableManpages = false; };
}
