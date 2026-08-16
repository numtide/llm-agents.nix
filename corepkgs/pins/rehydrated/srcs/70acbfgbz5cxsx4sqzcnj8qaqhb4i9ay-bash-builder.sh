export CONFIG_SHELL=$SHELL

# Normalize the NIX_BUILD_CORES variable. The value might be 0, which
# means that we're supposed to try and auto-detect the number of
# available CPU cores at run-time.
NIX_BUILD_CORES="${NIX_BUILD_CORES:-1}"
if ((NIX_BUILD_CORES <= 0)); then
  guess=$(nproc 2>/dev/null || true)
  ((NIX_BUILD_CORES = guess <= 0 ? 1 : guess))
fi
export NIX_BUILD_CORES

bash -eux $buildCommandPath
