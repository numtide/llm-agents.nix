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
# Upstream requires Zig 0.17.0-dev.813+2153f8143, not a released compiler.
stdenvNoCC.mkDerivation {
  pname = "codedb";
  inherit (source) version src;

  dontUnpack = true;
  dontBuild = true;
  dontStrip = true;

  installPhase = ''
    runHook preInstall

    install -Dm755 $src $out/bin/codedb
    install -Dm644 ${./LICENSE} $out/share/licenses/codedb/LICENSE
    install -Dm644 ${./bbtree-LICENSE} $out/share/licenses/codedb/bbtree-LICENSE

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
    license = licenses.bsd3;
    sourceProvenance = with sourceTypes; [ binaryNativeCode ];
    maintainers = with flake.lib.maintainers; [ smdex ];
    mainProgram = "codedb";
    platforms = source.platforms;
  };
}
