# The toolchain set: compilers/runtimes corepkgs builds WITH, threaded through the
# scope like `pins`. Single source of truth - the toolchain a constructor picks
# (toolchains.rust) IS the one exposed as packages.<name>. Bootstrap seam: pass a
# different `toolchains` to scope.nix (prebuilt today, GNU Mes from-source later)
# without touching a constructor. See [[corepkgs-bootstrap-direction]].
scope:
let
  inherit (scope)
    system
    seed
    nodeBin
    zigBin
    bunBin
    pnpmBin
    rustBin
    goBin
    pythonBin
    ;
in
{
  inherit seed;
  zig = zigBin;
  bun = bunBin;
  node = nodeBin;
  # pnpm runs on the node toolchain (a JS bundle); pnpm-bin pulls node from scope.
  pnpm = pnpmBin;
  rust = rustBin;
  go = goBin;
}
// (
  # python's manylinux external-lib pins are x86_64-only, so it ships there only.
  if system == "x86_64-linux" then { python = pythonBin; } else { }
)
