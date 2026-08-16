# amp (Sourcegraph's agentic coding CLI) - built on corepkgs, the repo's
# nixpkgs-free packaging system. `mkPackage` (from the flake scope) fetches the
# prebuilt release artifact and wraps it; version + per-platform hashes come
# from the shared ./hashes.json (the same file nix-update bumps), so nothing
# drifts.
#
# amp ships a bun --compile single-file binary: on Linux its appended JS payload
# segfaults on any ELF rewrite, so kind = "loader" leaves it byte-intact and
# invokes the pinned glibc loader through the wrapper. It shells out to ripgrep,
# so the pinned rg joins the wrapper PATH.
{
  mkPackage,
  mkUpdater,
  flake,
  corePins,
}:
let
  # system -> {platform} URL token, shared by the build and the updater.
  platforms = {
    x86_64-linux = "linux-x64";
    aarch64-linux = "linux-arm64";
    aarch64-darwin = "darwin-arm64";
  };
  urlTemplate = "https://static.ampcode.com/cli/{version}/amp-{platform}";
in
mkPackage {
  pname = "amp";
  hashesFile = ./hashes.json;
  inherit platforms urlTemplate;
  kind = "loader";

  runtimePkgs = [ corePins.ripgrep ];
  # keep the immutable Nix store binary from trying to replace itself.
  setEnv.AMP_SKIP_UPDATE_CHECK = "1";

  category = "AI Coding Agents";
  updater = mkUpdater {
    kind = "platform";
    inherit urlTemplate platforms;
    versionSource = {
      type = "text";
      url = "https://static.ampcode.com/cli/cli-version.txt";
    };
  };

  meta = {
    description = "CLI for Amp, an agentic coding tool in research preview from Sourcegraph";
    homepage = "https://ampcode.com/";
    changelog = "https://ampcode.com/chronicle";
    license = flake.lib.licenses.unfree;
    sourceProvenance = [ flake.lib.sourceTypes.binaryNativeCode ];
    maintainers = [ ];
  };
}
