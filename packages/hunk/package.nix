{
  lib,
  flake,
  stdenv,
  fetchFromGitHub,
  bun2nixLib,
  bun,
  bun-bin,
  makeWrapper,
  wrapBuddy,
  versionCheckHook,
  versionCheckHomeHook,
}:

let
  versionData = builtins.fromJSON (builtins.readFile ./hashes.json);
  inherit (versionData) version hash;
in
stdenv.mkDerivation {
  pname = "hunk";
  inherit version;

  src = fetchFromGitHub {
    owner = "modem-dev";
    repo = "hunk";
    tag = "v${version}";
    inherit hash;
  };

  nativeBuildInputs = [
    bun2nixLib.hook
    bun
    makeWrapper
  ]
  ++ lib.optionals stdenv.hostPlatform.isLinux [ wrapBuddy ];

  bunDeps = bun2nixLib.fetchBunDeps {
    bunNix = ./bun.nix;
  };

  dontUseBunBuild = true;
  dontUseBunInstall = true;
  dontRunLifecycleScripts = true;
  # `bun build --compile` embeds the JS bundle inside the executable;
  # stripping corrupts it.
  dontStrip = true;

  buildPhase = ''
    runHook preBuild

    # --watch needs a bun >= 1.3.14 runtime (modem-dev/hunk src/core/watch/runtime.ts).
    mkdir -p .bun-tmp .bun-install
    cp ${bun-bin}/share/bun-bin/* "$BUN_INSTALL_CACHE_DIR"/
    BUN_TMPDIR=$PWD/.bun-tmp \
    BUN_INSTALL=$PWD/.bun-install \
    ${lib.getExe bun} build --compile --no-compile-autoload-bunfig --target=${bun-bin.target} \
      ./packages/hunk/src/main.tsx ./packages/hunk/src/highlightWorkerEntry.ts \
      --outfile hunk-bin

    runHook postBuild
  '';

  # hunk finds skills/ by walking up from process.execPath, hence the wrapper.
  installPhase = ''
    runHook preInstall
    install -Dm755 ./hunk-bin $out/share/hunk/bin/hunk
    cp -r ./packages/hunk/skills $out/share/hunk/
    makeWrapper $out/share/hunk/bin/hunk $out/bin/hunk
    runHook postInstall
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [
    versionCheckHook
    versionCheckHomeHook
  ];

  passthru.category = "Code Review";

  meta = with lib; {
    description = "Terminal diff viewer for agentic changesets";
    homepage = "https://github.com/modem-dev/hunk";
    changelog = "https://github.com/modem-dev/hunk/releases/tag/v${version}";
    license = licenses.mit;
    sourceProvenance = with sourceTypes; [ fromSource ];
    maintainers = with flake.lib.maintainers; [ benvinegar ];
    mainProgram = "hunk";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
      "aarch64-darwin"
    ];
  };
}
