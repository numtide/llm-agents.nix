# cline (Cline autonomous coding agent CLI) - built on corepkgs, the repo's
# nixpkgs-free packaging system. `mkPackage` fetches the @cline/cli-<platform> npm
# tarball and wraps its bundled binary (package/bin/cline); version +
# per-platform hashes come from the shared ./hashes.json (the same file
# nix-update bumps), so nothing drifts.
#
# The artifact is a bun --compile single-file binary: patchelf shifts its
# appended JS payload and breaks bun's standalone-section lookup, so
# kind = "loader" runs it byte-intact through the pinned glibc loader on Linux;
# darwin links libSystem.
{
  mkPackage,
  flake,
}:
let
  # system -> {platform} URL token, shared by the build.
  platforms = {
    x86_64-linux = "linux-x64";
    aarch64-linux = "linux-arm64";
    aarch64-darwin = "darwin-arm64";
  };
  urlTemplate = "https://registry.npmjs.org/@cline/cli-{platform}/-/cli-{platform}-{version}.tgz";
in
mkPackage {
  pname = "cline";
  hashesFile = ./hashes.json;
  inherit platforms urlTemplate;
  unpack = "tar";
  binary = "package/bin/cline";
  kind = "loader";
  # A non-empty setEnv is required: mk-binary's empty-setEnv while-loop returns 1
  # under `set -e` and aborts the build before chmod. Marker var is harmless.
  setEnv = {
    CLINE_NIX_WRAPPED = "1";
  };

  category = "AI Coding Agents";

  meta = {
    description = "Autonomous coding agent CLI";
    homepage = "https://cline.bot";
    changelog = "https://github.com/cline/cline/releases";
    license = flake.lib.licenses.asl20;
    sourceProvenance = [ flake.lib.sourceTypes.binaryNativeCode ];
    maintainers = [ flake.lib.maintainers.poelzi ];
  };
}
