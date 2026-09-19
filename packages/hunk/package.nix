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

  # Pin every dependency to the exact version vendored in bun.nix.
  # bun's offline resolver refuses semver ranges (^/~) when only one
  # version is present in the store, so collapse them to exact pins.
  postPatch = ''
    for f in package.json packages/*/package.json; do
      if [ -f "$f" ]; then
        sed -i 's/: "\^/: "/g; s/: "~/: "/g' "$f"
      fi
    done
    sed -i 's/: "\^/: "/g; s/: "~/: "/g' bun.lock
  '';

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

  # The binary locates its bundled skills by walking the ancestors of
  # process.execPath for skills/<name>/SKILL.md (packages/hunk/src/core/run/
  # paths.ts), so the skills have to sit above the real executable. Both live
  # under share/hunk and $out/bin/hunk is a wrapper, which keeps the package
  # root free of a generic `skills` directory that collided with other
  # packages in buildEnv and home-manager profiles (#9364).
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
