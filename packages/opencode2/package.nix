# opencode2 - built on corepkgs, the repo's nixpkgs-free packaging system.
# `mkPackage` (from the flake scope) fetches the prebuilt npm tarball (next
# channel) and wraps it; version + per-platform hashes come from the shared
# ./hashes.json (the same file nix-update bumps), so nothing drifts.
#
# opencode2 ships a bun --compile single-file binary (package/bin/opencode2):
# on Linux its appended JS payload segfaults on any ELF rewrite, so kind =
# "loader" leaves it byte-intact and invokes the pinned glibc loader.
{
  mkPackage,
  mkUpdater,
  corePins,
  flake,
}:
let
  # system -> {platform} URL token, shared by the build and the updater.
  platforms = {
    x86_64-linux = "linux-x64";
    aarch64-linux = "linux-arm64";
    aarch64-darwin = "darwin-arm64";
  };
  urlTemplate = "https://registry.npmjs.org/@opencode-ai/cli-{platform}/-/cli-{platform}-{version}.tgz";
in
mkPackage {
  pname = "opencode2";
  hashesFile = ./hashes.json;
  inherit platforms urlTemplate;
  unpack = "tar";
  binary = "package/bin/opencode2";
  kind = "loader";
  runtimePkgs = [ corePins.ripgrep ];
  # Nix manages this binary; stop the CLI from trying to self-update.
  setEnv = {
    OPENCODE_DISABLE_AUTOUPDATE = "1";
  };

  category = "AI Coding Agents";
  updater = mkUpdater {
    kind = "platform";
    inherit urlTemplate platforms;
    versionSource = {
      type = "npm";
      package = "@opencode-ai/cli";
      tag = "next";
    };
  };

  meta = {
    description = "OpenCode 2 preview CLI";
    homepage = "https://opencode.ai";
    changelog = "https://github.com/anomalyco/opencode/commits/v2";
    license = flake.lib.licenses.mit;
    sourceProvenance = [ flake.lib.sourceTypes.binaryNativeCode ];
    maintainers = [ flake.lib.maintainers.iainlane ];
  };
}
