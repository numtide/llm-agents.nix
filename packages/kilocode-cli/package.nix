# kilocode-cli (`kilocode`) - built on corepkgs, the repo's nixpkgs-free
# packaging system. `mkPackage` (from the flake scope) fetches the prebuilt npm
# tarball and wraps it; version + per-platform hashes come from the shared
# ./hashes.json (the same file nix-update bumps), so nothing drifts.
#
# kilocode ships a bun --compile single-file binary (package/bin/kilo): on Linux
# its appended JS payload segfaults on any ELF rewrite, so kind = "loader" leaves
# it byte-intact and invokes the pinned glibc loader through the wrapper.
{
  mkPackage,
  mkUpdater,
  flake,
}:
let
  # system -> {platform} URL token, shared by the build and the updater.
  platforms = {
    x86_64-linux = "linux-x64";
    aarch64-linux = "linux-arm64";
    aarch64-darwin = "darwin-arm64";
  };
  urlTemplate = "https://registry.npmjs.org/@kilocode/cli-{platform}/-/cli-{platform}-{version}.tgz";
in
mkPackage {
  pname = "kilocode-cli";
  mainProgram = "kilocode";
  hashesFile = ./hashes.json;
  inherit platforms urlTemplate;
  unpack = "tar";
  binary = "package/bin/kilo";
  kind = "loader";

  category = "AI Coding Agents";
  updater = mkUpdater {
    kind = "platform";
    inherit urlTemplate platforms;
    versionSource = {
      type = "npm";
      package = "@kilocode/cli";
    };
  };

  meta = {
    description = "The open-source AI coding agent. Now available in your terminal.";
    homepage = "https://kilocode.ai/cli";
    changelog = "https://github.com/Kilo-Org/kilocode/releases";
    license = flake.lib.licenses.asl20;
    sourceProvenance = [ flake.lib.sourceTypes.binaryNativeCode ];
  };
}
