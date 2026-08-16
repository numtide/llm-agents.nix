export CONFIG_SHELL=$SHELL

# Normalize the NIX_BUILD_CORES variable. The value might be 0, which
# means that we're supposed to try and auto-detect the number of
# available CPU cores at run-time. We don't have nproc to detect the
# number of available CPU cores so default to 1 if not set.
NIX_BUILD_CORES="${NIX_BUILD_CORES:-1}"
if [ $NIX_BUILD_CORES -le 0 ]; then
  NIX_BUILD_CORES=1
fi
export NIX_BUILD_CORES

bash -eux $buildCommandPath
