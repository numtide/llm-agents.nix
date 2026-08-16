# coderabbit-cli (AI code-review CLI) - built on corepkgs, the repo's
# nixpkgs-free packaging system. `mkPackage` fetches the prebuilt release zip and
# wraps it; version + per-platform hashes come from the shared ./hashes.json (the
# same file nix-update bumps), so nothing drifts.
#
# The artifact is a bun --compile single-file binary: patchelf shifts its
# appended JS payload and breaks bun's standalone-section lookup, so
# kind = "loader" leaves it byte-intact and runs it through the pinned glibc
# loader on Linux; darwin links libSystem and runs directly.
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
  urlTemplate = "https://cli.coderabbit.ai/releases/{version}/coderabbit-{platform}.zip";
in
mkPackage {
  pname = "coderabbit-cli";
  mainProgram = "coderabbit";
  hashesFile = ./hashes.json;
  inherit platforms urlTemplate;
  unpack = "zip";
  binary = "coderabbit";
  kind = "loader";

  # `cr` is the short alias upstream installs alongside `coderabbit`.
  aliases = [ "cr" ];

  category = "Code Review";
  updater = mkUpdater {
    kind = "platform";
    inherit urlTemplate platforms;
    versionSource = {
      type = "text";
      url = "https://cli.coderabbit.ai/releases/latest/VERSION";
    };
  };

  meta = {
    description = "AI-powered code review CLI tool";
    homepage = "https://coderabbit.ai";
    changelog = "https://docs.coderabbit.ai/changelog";
    license = flake.lib.licenses.unfree;
    sourceProvenance = [ flake.lib.sourceTypes.binaryNativeCode ];
  };
}
