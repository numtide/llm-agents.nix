# cubic (AI code review CLI from cubic.dev) - built on corepkgs, the repo's
# nixpkgs-free packaging system. `mkPackage` (from the flake scope) fetches the
# prebuilt release zip and wraps it; version + per-platform hashes come from the
# shared ./hashes.json (the same file nix-update bumps), so nothing drifts.
#
# cubic ships a bun --compile single-file binary inside a zip: on Linux its
# appended JS payload segfaults on any ELF rewrite, so kind = "loader" leaves it
# byte-intact and invokes the pinned glibc loader through the wrapper.
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
  urlTemplate = "https://mcafvrhahbqdwfrtncql.supabase.co/storage/v1/object/public/releases/v{version}/cubic-{platform}.zip";
in
mkPackage {
  pname = "cubic";
  hashesFile = ./hashes.json;
  inherit platforms urlTemplate;
  unpack = "zip";
  binary = "cubic";
  kind = "loader";

  category = "Code Review";
  updater = mkUpdater {
    kind = "platform";
    inherit urlTemplate platforms;
    versionSource = {
      type = "text";
      url = "https://mcafvrhahbqdwfrtncql.supabase.co/storage/v1/object/public/releases/latest.txt";
    };
  };

  meta = {
    description = "AI code review CLI from cubic.dev - fast pre-flight review before you push";
    homepage = "https://cubic.dev";
    changelog = "https://docs.cubic.dev/ide/cli-review";
    license = flake.lib.licenses.unfree;
    sourceProvenance = [ flake.lib.sourceTypes.binaryNativeCode ];
    maintainers = [ flake.lib.maintainers.ryoppippi ];
  };
}
