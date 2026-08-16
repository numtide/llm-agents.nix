# qoder-cli-cn (Qoder CLI, mainland China edition) - built on corepkgs, the
# repo's nixpkgs-free packaging system. Same bun-compiled binary as qoder-cli,
# but the mainland-China service: separate release channel/CDN, binary name
# (qoderclicn) and account backend.
#
# qoderclicn is a bun --compile single-file binary, so kind = "loader" leaves
# it byte-intact and invokes the pinned glibc loader through the wrapper.
#
# version + each platform's url+hash live in ./hashes.json under `platforms`; we
# read the x86_64 entry in a let-block (the nested shape can't feed mkPackage's
# shared reader). The declarative updater tracks all upstream platforms.
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
  pname = "qoder-cli-cn";
  inherit (data) version;
  mainProgram = "qoderclicn";
  src = coreFetchurl {
    inherit (data.platforms.x86_64-linux) url hash;
  };
  unpack = "tar";
  binary = "qoderclicn";
  kind = "loader";
  # Disable self-update: the store binary is read-only, so an in-place update
  # attempt would just fail.
  setEnv = {
    QODER_DISABLE_AUTO_UPDATE = "1";
  };

  category = "AI Coding Agents";
  updater = mkUpdater {
    kind = "manifest";
    manifestUrl = "https://static.qoder.com.cn/qoder-cli-cn/channels/manifest.json";
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
    description = "Qoder CLI (mainland China edition) - terminal-based AI coding assistant for China-region accounts";
    platforms = [ "x86_64-linux" ];
    homepage = "https://qoder.cn";
    changelog = "https://qoder.cn/changelog";
    downloadPage = "https://qoder.cn/download";
    license = flake.lib.licenses.unfree;
    sourceProvenance = [ flake.lib.sourceTypes.binaryNativeCode ];
    maintainers = with flake.lib.maintainers; [ RyougiShiki-214 ];
  };
}
