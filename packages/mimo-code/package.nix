# mimo-code (Xiaomi's MiMoCode, an OpenCode-based coding agent) - built on
# corepkgs, the repo's nixpkgs-free packaging system. `mkPackage` fetches the
# prebuilt release tarball and wraps it; version + per-platform hashes come from
# the shared ./hashes.json.
#
# mimo is a bun --compile single-file binary, so kind = "loader" leaves it
# byte-intact and invokes the pinned glibc loader through the wrapper. It shells
# out to ripgrep, pinned onto PATH.
#
# The darwin asset is a .zip while linux ships .tar.gz, so unpack = "auto" infers
# the archive kind per platform from the resolved URL extension.
{
  mkPackage,
  mkUpdater,
  corePins,
  flake,
}:
let
  # system -> {platform} release asset, shared by the build and the updater.
  platforms = {
    x86_64-linux = "mimocode-linux-x64.tar.gz";
    aarch64-linux = "mimocode-linux-arm64.tar.gz";
    aarch64-darwin = "mimocode-darwin-arm64.zip";
  };
  urlTemplate = "https://github.com/XiaomiMiMo/MiMo-Code/releases/download/v{version}/{platform}";
in
mkPackage {
  pname = "mimo-code";
  hashesFile = ./hashes.json;
  inherit platforms urlTemplate;
  unpack = "auto";
  binary = "mimo";
  mainProgram = "mimo";
  kind = "loader";
  runtimePkgs = [ corePins.ripgrep ];
  # Inert marker; also keeps setEnv non-empty (a historical wrapper-generation
  # quirk). mimo does not read it.
  setEnv = {
    MIMO_CODE_NAKED = "1";
  };

  category = "AI Coding Agents";
  updater = mkUpdater {
    kind = "platform";
    inherit urlTemplate platforms;
    versionSource = {
      type = "github";
      owner = "XiaomiMiMo";
      repo = "MiMo-Code";
    };
  };

  meta = {
    description = "Open-source AI coding agent with cross-session memory";
    longDescription = ''
      MiMoCode is a terminal-native AI coding assistant based on OpenCode.
      It adds persistent memory, context management, subagent orchestration,
      goal-driven autonomous loops, and compose workflows.
    '';
    homepage = "https://github.com/XiaomiMiMo/MiMo-Code";
    changelog = "https://github.com/XiaomiMiMo/MiMo-Code/releases";
    license = flake.lib.licenses.mit;
    sourceProvenance = [ flake.lib.sourceTypes.binaryNativeCode ];
    maintainers = [ flake.lib.maintainers.scotttrinh ];
  };
}
