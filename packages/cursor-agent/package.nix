# cursor-agent (Cursor's terminal coding agent) - built on corepkgs, the repo's
# nixpkgs-free packaging system. `mkPackage` fetches the prebuilt release artifact
# and wraps it; version + per-platform hashes come from the shared ./hashes.json
# (the same file nix-update bumps), so nothing drifts.
#
# The release is a whole package dir (node + rg + a bundled native module), so
# dir-install the extracted tree and patchelf every ELF inside it. The bundled
# file_service.*.node needs libz, and the agent shells out to coreutils.
{
  mkPackage,
  mkUpdater,
  flake,
  corePins,
}:
let
  # system -> {platform} URL token, shared by the build and the updater.
  platforms = {
    x86_64-linux = "linux/x64";
    aarch64-linux = "linux/arm64";
    aarch64-darwin = "darwin/arm64";
  };
  urlTemplate = "https://downloads.cursor.com/lab/{version}/{platform}/agent-cli-package.tar.gz";
in
mkPackage {
  pname = "cursor-agent";
  hashesFile = ./hashes.json;
  inherit platforms urlTemplate;
  unpack = "tar";
  installDir = "dist-package";
  kind = "patchelf";
  libs = [ corePins.zlib ]; # a bundled native node module (file_service.*.node) needs libz
  runtimePkgs = [ corePins.coreutils ];

  category = "AI Coding Agents";
  updater = mkUpdater {
    kind = "platform";
    inherit urlTemplate platforms;
    versionSource = {
      type = "text";
      url = "https://cursor.com/install";
      regex = "downloads\\.cursor\\.com/lab/([0-9]{4}\\.[0-9]{2}\\.[0-9]{2}-[0-9a-f-]+)/";
    };
  };

  meta = {
    description = "Cursor Agent - CLI tool for Cursor AI code editor";
    homepage = "https://cursor.com/";
    changelog = "https://www.cursor.com/changelog";
    license = flake.lib.licenses.unfree;
    sourceProvenance = [ flake.lib.sourceTypes.binaryNativeCode ];
    maintainers = [ ];
  };
}
