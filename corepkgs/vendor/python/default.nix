# Vendor a Python app + its runtime deps as ONE fixed-output derivation. `pip
# install --target` builds the app via its PEP 517 backend and resolves the full
# closure from PyPI (manylinux wheels + pure-python) into a flat site tree we
# output. pip's per-file hashes aren't a single fetchurl input, so it's one
# committed-hash FOD.
#
# Determinism: --no-compile (no timestamped .pyc), and strip install bookkeeping
# that embeds the build path (RECORD, direct_url.json) or timestamps
# (__pycache__). Sdist-only C-compile deps are out of scope (wheels are compiler-free).
scope:
{
  src,
  pythonDepsHash,
  sourceRoot ? null,
  postPatch ? "",
  python, # the python toolchain, threaded from the constructor scope
}:
let
  inherit (scope) mkDrvSh;
in
mkDrvSh {
  name = "python-vendor";
  outputHash = pythonDepsHash;
  env = {
    inherit src postPatch;
    sourceRoot = if sourceRoot == null then "" else sourceRoot;
    python = "${python}";
  };
  script = ./builder.sh;
}
