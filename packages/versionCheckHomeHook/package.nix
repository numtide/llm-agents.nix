{
  lib,
  makeSetupHook,
}:

makeSetupHook {
  name = "version-check-home-hook";
  passthru.hideFromDocs = true;
  passthru.skipUpdate = true;
  meta = {
    description = "Setup hook that provides a writable HOME for versionCheckHook";
    license = lib.licenses.mit;
    platforms = lib.platforms.all;
  };
} ./version-check-home.sh
