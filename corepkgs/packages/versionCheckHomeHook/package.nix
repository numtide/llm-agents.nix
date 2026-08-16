# versionCheckHomeHook: gives versionCheckHook a writable $HOME (CLI tools that
# create config/cache dirs fail without it).
{
  lib,
  makeSetupHook,
}:

makeSetupHook {
  name = "version-check-home-hook";
  passthru.hideFromDocs = true;
  meta = {
    description = "Setup hook that provides a writable HOME for versionCheckHook";
    license = lib.licenses.mit;
    platforms = lib.platforms.all;
  };
} ./version-check-home.sh
