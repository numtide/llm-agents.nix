{
  stdenv,
  fetchurl,
  flake,
  mkUpdater,
  qoder-cli,
}:

let
  versionData = builtins.fromJSON (builtins.readFile ./hashes.json);
  inherit (versionData) version platforms;

  srcFor =
    system:
    fetchurl {
      inherit (platforms.${system} or (throw "Unsupported system: ${system}")) url hash;
    };
in
# Same bun-compiled binary as qoder-cli, but built for the mainland China
# service: separate release channel/CDN, binary name and account backend.
qoder-cli.overrideAttrs (old: {
  pname = "qoder-cli-cn";
  inherit version;

  src = srcFor stdenv.hostPlatform.system;

  installPhase = ''
    runHook preInstall

    install -Dm755 qoderclicn $out/bin/qoderclicn

    runHook postInstall
  '';

  codesignTeamId = "9DFNGU9AK5";
  codesignSources = [ (srcFor "aarch64-darwin") ];

  passthru = old.passthru // {
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
  };

  meta = old.meta // {
    description = "Qoder CLI (mainland China edition) - terminal-based AI coding assistant for China-region accounts";
    homepage = "https://qoder.cn";
    changelog = "https://qoder.cn/changelog";
    downloadPage = "https://qoder.cn/download";
    maintainers = with flake.lib.maintainers; [ RyougiShiki-214 ];
    mainProgram = "qoderclicn";
  };
})
