# qoder-cli (Qoder's `qodercli` AI coding assistant) - built on corepkgs, the
# repo's nixpkgs-free packaging system. `mkPackage` fetches the prebuilt release
# tarball and wraps it.
#
# qodercli is a bun --compile single-file binary, so kind = "loader" leaves it
# byte-intact and invokes the pinned glibc loader through the wrapper.
#
# version + each platform's url+hash live in ./hashes.json under `platforms`; the
# nested shape can't feed mkPackage's shared reader, so we read the x86_64 entry
# in a let-block. The declarative updater tracks all upstream platforms.
{
  mkPackage,
  mkUpdater,
  coreFetchurl,
  flake,
}:
let
  data = builtins.fromJSON (builtins.readFile ./hashes.json);
in
mkPackage {
  pname = "qoder-cli";
  inherit (data) version;
  mainProgram = "qodercli";
  src = coreFetchurl {
    inherit (data.platforms.x86_64-linux) url hash;
  };
  unpack = "tar";
  binary = "qodercli";
  kind = "loader";
  # Disable self-update: the store binary is read-only, so an in-place update
  # attempt would just fail.
  setEnv = {
    QODER_DISABLE_AUTO_UPDATE = "1";
  };

  category = "AI Coding Agents";
  updater = mkUpdater {
    kind = "manifest";
    manifestUrl = "https://qoder-ide.oss-ap-southeast-1.aliyuncs.com/qodercli/channels/manifest.json";
    platformMap = [
      {
        os = "linux";
        arch = "amd64";
        platform = "x86_64-linux";
      }
      {
        os = "linux";
        arch = "arm64";
        platform = "aarch64-linux";
      }
      {
        os = "darwin";
        arch = "arm64";
        platform = "aarch64-darwin";
      }
    ];
  };

  meta = {
    description = "Qoder AI CLI tool - Terminal-based AI assistant for code development";
    platforms = [ "x86_64-linux" ];
    homepage = "https://qoder.com";
    changelog = "https://qoder.com/changelog";
    downloadPage = "https://qoder.com/download";
    license = flake.lib.licenses.unfree;
    sourceProvenance = [ flake.lib.sourceTypes.binaryNativeCode ];
    maintainers = [ ];
  };
}
