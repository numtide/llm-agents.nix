{
  lib,
  flake,
  stdenvNoCC,
  platformSource,
  mkUpdater,
  versionCheckHook,
  versionCheckHomeHook,
  codesignCheckHook,
  mkCodesignCheck,
}:

let
  source = platformSource {
    hashesFile = ./hashes.json;
    platforms = {
      x86_64-linux = "linux-x86_64";
      aarch64-linux = "linux-arm64";
      x86_64-darwin = "darwin-x86_64";
      aarch64-darwin = "darwin-arm64";
    };
    urlTemplate = "https://github.com/justrach/codedb/releases/download/v{version}/codedb-{platform}";
  };
  teamId = "WWP9DLJ27P";
in
# Upstream builds with a Zig dev snapshot.
stdenvNoCC.mkDerivation {
  pname = "codedb";
  inherit (source) version src;

  dontUnpack = true;
  dontStrip = true;

  installPhase = ''
    runHook preInstall

    install -Dm755 $src $out/bin/codedb

    runHook postInstall
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [
    versionCheckHook
    versionCheckHomeHook
  ]
  ++ lib.optionals stdenvNoCC.hostPlatform.isDarwin [ codesignCheckHook ];
  codesignTeamId = teamId;

  passthru = {
    category = "Memory & Code Intelligence";
    tests.codesign = mkCodesignCheck {
      name = "codedb";
      inherit teamId;
      srcs = source.darwinSrcs;
    };
    updater = mkUpdater (
      source.updater
      // {
        versionSource = {
          type = "github";
          owner = "justrach";
          repo = "codedb";
        };
      }
    );
  };

  meta = with lib; {
    description = "Code intelligence server, CLI, and MCP tools for AI agents";
    homepage = "https://github.com/justrach/codedb";
    changelog = "https://github.com/justrach/codedb/releases/tag/v${source.version}";
    license = with licenses; [
      bsd3
      mit # vendored bbtree
    ];
    sourceProvenance = with sourceTypes; [ binaryNativeCode ];
    maintainers = with flake.lib.maintainers; [ smdex ];
    mainProgram = "codedb";
    platforms = source.platforms;
  };
}
