# writeShellApplication lints its wrapper script with shellcheck (Haskell) in a
# build-time checkPhase. That drags the whole GHC closure into evaluation - it
# was ~35% of the dev-shell eval, pulled in transitively by every wrapper
# (mypy-check, the launcher, per-package updateScripts) even though shellcheck
# is only a build input, never a runtime dep.
#
# We lint shell with shuck (Rust) instead, so default that check off across the
# whole package set. `checkPhase ? null` selects the shellcheck branch; setting
# it to "" skips it and never references shellcheck-minimal, so GHC never enters
# eval. Explicit callers can still pass their own checkPhase to opt back in.
_final: prev: {
  writeShellApplication =
    args: prev.writeShellApplication (args // { checkPhase = args.checkPhase or ""; });
}
