# jules (Google's asynchronous coding agent CLI) - built on corepkgs, the repo's
# nixpkgs-free packaging system. `mkPackage` fetches the prebuilt release tarball
# and wraps it; version + per-platform hashes come from the shared ./hashes.json
# (the same file nix-update bumps), so nothing drifts.
#
# The artifact is a normal dynamic Go ELF, so kind = "patchelf" rewrites its
# interpreter/rpath to the pinned glibc on Linux; darwin links libSystem.
{
  mkPackage,
  mkUpdater,
  flake,
}:
let
  # system -> {platform} URL token, shared by the build and the updater.
  platforms = {
    x86_64-linux = "linux_amd64";
    aarch64-linux = "linux_arm64";
    aarch64-darwin = "darwin_arm64";
  };
  urlTemplate = "https://storage.googleapis.com/jules-cli/v{version}/jules_external_v{version}_{platform}.tar.gz";
in
mkPackage {
  pname = "jules";
  hashesFile = ./hashes.json;
  inherit platforms urlTemplate;
  unpack = "tar";
  binary = "jules";
  kind = "patchelf";

  category = "AI Coding Agents";
  updater = mkUpdater {
    kind = "platform";
    inherit urlTemplate platforms;
    versionSource = {
      type = "npm";
      package = "@google/jules";
    };
  };

  meta = {
    description = "Jules, the asynchronous coding agent from Google, in the terminal";
    homepage = "https://jules.google";
    changelog = "https://jules.google/docs/changelog";
    license = flake.lib.licenses.unfree;
    sourceProvenance = [ flake.lib.sourceTypes.binaryNativeCode ];
  };
}
