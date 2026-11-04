{
  lib,
  makeSetupHook,
}:

makeSetupHook {
  name = "unpin-cargo-msrv-hook";
  passthru.hideFromDocs = true;
  passthru.skipUpdate = true;
  meta = {
    description = "Setup hook that removes rust-version (MSRV) constraints from Cargo manifests";
    license = lib.licenses.mit;
    platforms = lib.platforms.all;
  };
} ./unpin-cargo-msrv.sh
