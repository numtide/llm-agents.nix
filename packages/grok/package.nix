# grok (xAI's agentic coding CLI) - built on corepkgs, the repo's nixpkgs-free
# packaging system. `mkPackage` (from the flake scope) fetches the prebuilt
# release artifact and wraps it; version + per-platform hashes come from the
# shared ./hashes.json (the same file nix-update bumps), so nothing drifts.
#
# grok ships a bun --compile single-file binary: on Linux its appended JS
# payload segfaults on any ELF rewrite, so kind = "loader" leaves it byte-intact
# and invokes the pinned glibc loader through the wrapper; on darwin it links
# the system libSystem and just runs.
{
  mkPackage,
  mkUpdater,
  flake,
}:
let
  # system -> {platform} URL token, shared by the build and the updater.
  platforms = {
    x86_64-linux = "linux-x86_64";
    aarch64-linux = "linux-aarch64";
    aarch64-darwin = "macos-aarch64";
  };
  urlTemplate = "https://storage.googleapis.com/grok-build-public-artifacts/cli/grok-{version}-{platform}";
in
mkPackage {
  pname = "grok";
  hashesFile = ./hashes.json;
  inherit platforms urlTemplate;
  kind = "loader";

  # Current Grok resolves its shell via $SHELL / PATH, so no bubblewrap shim is
  # needed (the former one broke host tools, #4912/#4913). --no-auto-update
  # keeps the immutable Nix store binary from trying to replace itself; `agent`
  # is grok's agent-mode entrypoint (argv0 dispatch).
  extraArgs = [ "--no-auto-update" ];
  aliases = [ "agent" ];

  category = "AI Coding Agents";
  updater = mkUpdater {
    kind = "platform";
    inherit urlTemplate platforms;
    versionSource = {
      type = "text";
      url = "https://storage.googleapis.com/grok-build-public-artifacts/cli/stable";
    };
  };

  meta = {
    description = "Grok Build, xAI's agentic coding tool";
    homepage = "https://x.ai";
    changelog = "https://x.ai";
    license = flake.lib.licenses.unfree;
    sourceProvenance = [ flake.lib.sourceTypes.binaryNativeCode ];
    maintainers = [ flake.lib.maintainers.ryoppippi ];
  };
}
