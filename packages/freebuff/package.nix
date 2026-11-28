{
  mkUpdater,
  lib,
  stdenv,
  platformSource,
  makeWrapper,
  wrapBuddy,
  ripgrep,
  versionCheckHook,
  versionCheckHomeHook,
}:

let
  source = platformSource {
    hashesFile = ./hashes.json;
    platforms = {
      x86_64-linux = "linux-x64";
      aarch64-linux = "linux-arm64";
      aarch64-darwin = "darwin-arm64";
    };
    urlTemplate = "https://github.com/CodebuffAI/codebuff-community/releases/download/freebuff-v{version}/freebuff-{platform}.tar.gz";
  };
in
stdenv.mkDerivation {
  pname = "freebuff";
  inherit (source) version src;

  nativeBuildInputs = [
    makeWrapper
  ]
  ++ lib.optionals stdenv.hostPlatform.isLinux [ wrapBuddy ];

  sourceRoot = ".";

  dontStrip = true; # bun runtime embeds JS at the tail of the binary

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin
    install -m755 freebuff $out/bin/freebuff
    install -m644 tree-sitter.wasm $out/bin/tree-sitter.wasm

    wrapProgram $out/bin/freebuff \
      --argv0 freebuff \
      --prefix PATH : ${lib.makeBinPath [ ripgrep ]}

    runHook postInstall
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [
    versionCheckHook
    versionCheckHomeHook
  ];
  versionCheckProgramArg = "--version";

  passthru.category = "AI Coding Agents";

  passthru.updater = mkUpdater { kind = "script"; };

  meta = with lib; {
    description = "The world's strongest free coding agent";
    homepage = "https://freebuff.com";
    changelog = "https://github.com/CodebuffAI/codebuff-community/releases/tag/freebuff-v${source.version}";
    license = licenses.asl20;
    sourceProvenance = with sourceTypes; [ binaryNativeCode ];
    maintainers = with maintainers; [ ocfox ];
    platforms = source.platforms;
    mainProgram = "freebuff";
  };
}
