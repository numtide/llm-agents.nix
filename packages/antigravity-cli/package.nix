# antigravity-cli (Google Antigravity's agentic dev CLI) - built on corepkgs,
# the repo's nixpkgs-free packaging system. `mkPackage` fetches the prebuilt
# release tarball and wraps it; version + per-platform hashes come from the
# shared ./hashes.json (the same file the updater bumps).
#
# A normal dynamic ELF, so kind = "patchelf": formatelf rewrites the interpreter
# + rpath to the pinned glibc/gccLib. All three platforms ship a .tar.gz.
#
# NOTE: the release URL carries an opaque build id ("...-6057583128215552/...")
# that is not derivable from the version, so it is baked into urlTemplate. On a
# version bump the build id must be refreshed here too (upstream has no stable
# per-version download URL; the custom update.py tracks the full urls).
{
  mkPackage,
  corePins,
  flake,
}:
let
  # system -> {platform} URL tail, filled into urlTemplate per system.
  platforms = {
    x86_64-linux = "linux-x64/cli_linux_x64.tar.gz";
    aarch64-linux = "linux-arm/cli_linux_arm64.tar.gz";
    aarch64-darwin = "darwin-arm/cli_mac_arm64.tar.gz";
  };
  urlTemplate = "https://storage.googleapis.com/antigravity-public/antigravity-cli/{version}-6057583128215552/{platform}";
in
mkPackage {
  pname = "antigravity-cli";
  hashesFile = ./hashes.json;
  inherit platforms urlTemplate;
  unpack = "tar";
  binary = "antigravity";
  mainProgram = "agy";
  kind = "patchelf";
  libs = [ corePins.gccLib ];

  category = "AI Coding Agents";

  meta = {
    description = "CLI for Google Antigravity, an agentic development platform";
    homepage = "https://antigravity.google/";
    changelog = "https://antigravity.google/cli";
    license = flake.lib.licenses.unfree;
    sourceProvenance = [ flake.lib.sourceTypes.binaryNativeCode ];
    maintainers = [ flake.lib.maintainers.ryoppippi ];
  };
}
