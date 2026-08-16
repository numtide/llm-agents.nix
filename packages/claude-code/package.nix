# claude-code (Anthropic's agentic coding CLI) - built on corepkgs, the repo's
# nixpkgs-free packaging system. `mkPackage` fetches the prebuilt release artifact
# and wraps it; version + per-platform hashes come from the shared ./hashes.json
# (the same file nix-update bumps), so nothing drifts.
#
# claude ships a bun --compile single-file binary: on Linux its appended JS
# payload segfaults on any ELF rewrite, so kind = "loader" leaves it byte-intact
# and invokes the pinned glibc loader through the wrapper; on darwin it links the
# system libSystem and just runs. bubblewrap + socat back the sandbox.
{
  mkPackage,
  mkUpdater,
  flake,
  corePins,
  lib,
  system,
}:
let
  # system -> {platform} URL token, shared by the build and the updater.
  platforms = {
    x86_64-linux = "linux-x64";
    aarch64-linux = "linux-arm64";
    aarch64-darwin = "darwin-arm64";
  };
  urlTemplate = "https://storage.googleapis.com/claude-code-dist-86c565f3-f756-42ad-8dfa-d59b1c096819/claude-code-releases/{version}/{platform}/claude";
in
mkPackage {
  pname = "claude-code";
  mainProgram = "claude";
  hashesFile = ./hashes.json;
  inherit platforms urlTemplate;
  kind = "loader";

  # bubblewrap + socat provide the sandbox; env disables auto-update, the
  # installation-method warnings, and non-essential model calls. DISABLE_TELEMETRY
  # / CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC are intentionally left unset - both
  # break remote-control (see numtide/llm-agents.nix#2811).
  #
  # bubblewrap + socat are Linux-only (namespaces); on darwin claude-code runs
  # without the bwrap sandbox, so drop them there rather than fail to build.
  runtimePkgs = lib.optionals (lib.hasSuffix "-linux" system) [
    corePins.bubblewrap
    corePins.socat
  ];
  setEnv = {
    DISABLE_AUTOUPDATER = "1";
    DISABLE_INSTALLATION_CHECKS = "1";
    DISABLE_NON_ESSENTIAL_MODEL_CALLS = "1";
  };

  category = "AI Coding Agents";
  updater = mkUpdater {
    kind = "manifest-checksums";
    versionSource = {
      type = "text";
      url = "https://storage.googleapis.com/claude-code-dist-86c565f3-f756-42ad-8dfa-d59b1c096819/claude-code-releases/latest";
    };
    manifestUrl = "https://storage.googleapis.com/claude-code-dist-86c565f3-f756-42ad-8dfa-d59b1c096819/claude-code-releases/{version}/manifest.json";
    checksumPath = "platforms.{platform}.checksum";
    # The same tokens key both the download URL and the manifest checksums.
    inherit platforms;
    # Anthropic yanks bad releases by repointing `latest`, so follow it down.
    versionPolicy = "follow_pointer";
  };

  meta = {
    description = "Agentic coding tool that lives in your terminal, understands your codebase, and helps you code faster";
    homepage = "https://claude.ai/code";
    changelog = "https://github.com/anthropics/claude-code/releases";
    license = flake.lib.licenses.unfree;
    sourceProvenance = [ flake.lib.sourceTypes.binaryNativeCode ];
    maintainers = [
      flake.lib.maintainers.malo
      flake.lib.maintainers.omarjatoi
      flake.lib.maintainers.ryoppippi
    ];
  };
}
