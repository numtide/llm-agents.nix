# opencode - built on corepkgs, the repo's nixpkgs-free packaging system.
# `mkPackage` (from the flake scope) fetches the prebuilt release tarball and
# wraps it; version + per-platform hashes come from the shared ./hashes.json
# (the same file nix-update bumps), so nothing drifts.
#
# opencode ships a bun --compile single-file binary: on Linux its appended JS
# payload segfaults on any ELF rewrite, so kind = "loader" leaves it byte-intact
# and invokes the pinned glibc loader through the wrapper; on darwin it links
# libSystem and just runs. The linux assets are tar.gz and the darwin asset is a
# .zip, so unpack = "auto" infers the archive kind per platform from the URL.
{
  mkPackage,
  mkUpdater,
  corePins,
  flake,
}:
mkPackage {
  pname = "opencode";
  hashesFile = ./hashes.json;
  urlTemplate = "https://github.com/anomalyco/opencode/releases/download/v{version}/{platform}";
  platforms = {
    x86_64-linux = "opencode-linux-x64.tar.gz";
    aarch64-linux = "opencode-linux-arm64.tar.gz";
    aarch64-darwin = "opencode-darwin-arm64.zip";
  };
  unpack = "auto";
  binary = "opencode";
  kind = "loader";
  runtimePkgs = [ corePins.ripgrep ];
  # Nix manages this binary; stop the CLI from trying to self-update.
  setEnv = {
    OPENCODE_DISABLE_AUTOUPDATE = "1";
  };

  category = "AI Coding Agents";
  updater = mkUpdater {
    kind = "platform";
    versionSource = {
      type = "github";
      owner = "anomalyco";
      repo = "opencode";
    };
    urlTemplate = "https://github.com/anomalyco/opencode/releases/download/v{version}/{platform}";
    platforms = {
      x86_64-linux = "opencode-linux-x64.tar.gz";
      aarch64-linux = "opencode-linux-arm64.tar.gz";
      aarch64-darwin = "opencode-darwin-arm64.zip";
    };
  };

  meta = {
    description = "AI coding agent built for the terminal";
    homepage = "https://github.com/anomalyco/opencode";
    changelog = "https://github.com/anomalyco/opencode/releases";
    license = flake.lib.licenses.mit;
    sourceProvenance = [ flake.lib.sourceTypes.binaryNativeCode ];
  };
}
