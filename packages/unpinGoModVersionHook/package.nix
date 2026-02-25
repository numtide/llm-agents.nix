{
  lib,
  makeSetupHook,
}:

makeSetupHook {
  name = "unpin-go-mod-version-hook";
  meta = {
    description = "Setup hook that relaxes go.mod version constraints to match the build toolchain";
    license = lib.licenses.mit;
    platforms = lib.platforms.all;
  };
} ./unpin-go-mod-version.sh
