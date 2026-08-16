# open-code-review (`ocr`, Alibaba's AI code-review CLI) - built on corepkgs, the
# repo's nixpkgs-free packaging system. `mkPackage` fetches the prebuilt release
# artifact and wraps it; version + per-platform hashes come from the shared
# ./hashes.json (the same file nix-update bumps), so nothing drifts.
#
# Upstream ships a single dynamic Go binary per platform, so patchelf its
# interpreter/rpath to the pinned glibc and expose it as `ocr`.
{
  mkPackage,
  mkUpdater,
  flake,
}:
let
  # system -> {platform} URL token, shared by the build and the updater.
  platforms = {
    x86_64-linux = "linux-amd64";
    aarch64-linux = "linux-arm64";
    aarch64-darwin = "darwin-arm64";
  };
  urlTemplate = "https://github.com/alibaba/open-code-review/releases/download/v{version}/opencodereview-{platform}";
in
mkPackage {
  pname = "open-code-review";
  mainProgram = "ocr";
  hashesFile = ./hashes.json;
  inherit platforms urlTemplate;
  unpack = "none";
  kind = "patchelf";

  category = "Code Review";
  updater = mkUpdater {
    kind = "platform";
    inherit urlTemplate platforms;
    versionSource = {
      type = "github";
      owner = "alibaba";
      repo = "open-code-review";
    };
  };

  meta = {
    description = "AI-powered code review CLI";
    homepage = "https://github.com/alibaba/open-code-review";
    changelog = "https://github.com/alibaba/open-code-review/releases";
    license = flake.lib.licenses.asl20;
    sourceProvenance = [ flake.lib.sourceTypes.binaryNativeCode ];
    maintainers = [ flake.lib.maintainers.fridh ];
  };
}
