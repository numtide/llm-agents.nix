# forgecode (`forge`, an AI-enhanced terminal dev environment) - built on
# corepkgs, the repo's nixpkgs-free packaging system. `mkPackage` (from the flake
# scope) fetches the prebuilt release artifact and wraps it; version +
# per-platform hashes come from the shared ./hashes.json (the same file
# nix-update bumps), so nothing drifts.
#
# forge is a normal dynamic ELF, so kind = "patchelf" rewrites its interpreter
# and rpath to the pinned glibc (+ gccLib, already in the default libpath, which
# supplies libgcc_s).
{
  mkPackage,
  mkUpdater,
  flake,
}:
let
  # system -> {platform} URL token, shared by the build and the updater.
  platforms = {
    x86_64-linux = "x86_64-unknown-linux-gnu";
    aarch64-linux = "aarch64-unknown-linux-gnu";
    aarch64-darwin = "aarch64-apple-darwin";
  };
  urlTemplate = "https://github.com/tailcallhq/forgecode/releases/download/v{version}/forge-{platform}";
in
mkPackage {
  pname = "forgecode";
  mainProgram = "forge";
  hashesFile = ./hashes.json;
  inherit platforms urlTemplate;
  kind = "patchelf";

  # Forge phones home on every start and, if a newer release exists, runs
  # `curl -fsSL https://forgecode.dev/cli | sh` which drops a mutable copy into
  # ~/.local/bin and shadows the Nix-managed binary. Force update off so the
  # store path stays authoritative (issue #5976).
  setEnv = {
    FORGE_UPDATES__FREQUENCY = "never";
    FORGE_UPDATES__AUTO_UPDATE = "false";
  };

  category = "AI Coding Agents";
  updater = mkUpdater {
    kind = "platform";
    inherit urlTemplate platforms;
    versionSource = {
      type = "github";
      owner = "tailcallhq";
      repo = "forgecode";
    };
  };

  meta = {
    description = "AI-Enhanced Terminal Development Environment - A comprehensive coding agent that integrates AI capabilities with your development environment";
    homepage = "https://github.com/tailcallhq/forgecode";
    changelog = "https://github.com/tailcallhq/forgecode/releases";
    license = flake.lib.licenses.mit;
    sourceProvenance = [ flake.lib.sourceTypes.binaryNativeCode ];
    maintainers = [ flake.lib.maintainers.mic92 ];
  };
}
