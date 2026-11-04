{
  lib,
  stdenv,
  fetchFromGitHub,
  bun2nixLib,
  bun,
  python3,
  versionCheckHook,
  versionCheckHomeHook,
}:

let
  versionData = builtins.fromJSON (builtins.readFile ./hashes.json);
  inherit (versionData) version hash;

  platformMap = {
    x86_64-linux = "bun-linux-x64";
    aarch64-linux = "bun-linux-arm64";
    aarch64-darwin = "bun-darwin-arm64";
  };

  platform = stdenv.hostPlatform.system;
  bunTarget = platformMap.${platform} or (throw "Unsupported system: ${platform}");
in
stdenv.mkDerivation {
  pname = "plannotator";
  inherit version;

  src = fetchFromGitHub {
    owner = "backnotprop";
    repo = "plannotator";
    tag = "v${version}";
    inherit hash;
  };

  nativeBuildInputs = [
    bun2nixLib.hook
    bun
  ];

  patches = lib.optionals ((builtins.readFile ./fix-stale-bun-lock.patch) != "") [
    ./fix-stale-bun-lock.patch
  ];

  # Bun still tries registry manifest lookups for a few workspace deps even
  # with --offline and a populated bun2nix cache. Rewrite the workspace
  # manifests to the lockfile's exact, cache-backed package versions first.
  postPatch = ''
    ${lib.getExe python3} ${./fix-bun-offline-install.py}
  '';

  bunDeps = bun2nixLib.fetchBunDeps {
    bunNix = ./bun.nix;
  };

  bunInstallFlags = "--linker=isolated --offline";

  dontUseBunBuild = true;
  dontUseBunInstall = true;
  dontRunLifecycleScripts = true;

  # bun build --compile embeds the JS bundle inside the executable; stripping
  # corrupts it.
  dontStrip = true;

  buildPhase = ''
    runHook preBuild

    mkdir -p .bun-tmp .bun-install
    export BUN_TMPDIR=$PWD/.bun-tmp
    export BUN_INSTALL=$PWD/.bun-install

    # Normally upstream's postinstall, which dontRunLifecycleScripts skips. A
    # viewer built here could differ from the bytes published on guides.show,
    # so keep the fallback pin instead of `build:viewer-pin`.
    bun apps/guides-show/build/sync-manifest.ts --if-missing

    bun run build:review
    bun run build:hook
    bun build apps/hook/server/index.ts \
      --compile \
      --no-compile-autoload-bunfig \
      --target=${bunTarget} \
      --define '__CLI_VERSION__="${version}"' \
      --outfile plannotator

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    install -Dm755 plannotator $out/bin/plannotator

    runHook postInstall
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [
    versionCheckHook
    versionCheckHomeHook
  ];
  versionCheckProgramArg = [ "--version" ];

  passthru.category = "Code Review";

  meta = with lib; {
    description = "Interactive plan and code review tool for AI coding agents";
    homepage = "https://github.com/backnotprop/plannotator";
    changelog = "https://github.com/backnotprop/plannotator/releases/tag/v${version}";
    license = with licenses; [
      mit
      asl20
    ];
    sourceProvenance = with sourceTypes; [ fromSource ];
    maintainers = with maintainers; [ nwjsmith ];
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
      "aarch64-darwin"
    ];
    mainProgram = "plannotator";
  };
}
