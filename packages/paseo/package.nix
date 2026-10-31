# Adapted from https://github.com/getpaseo/paseo/blob/v0.13.2/nix/package.nix.
{
  lib,
  stdenv,
  flake,
  buildNpmPackage,
  fetchFromGitHub,
  nodejs_22,
  python3,
  makeWrapper,
  formatelf,
  libuv,
  versionCheckHook,
  versionCheckHomeHook,
}:

buildNpmPackage (finalAttrs: {
  pname = "paseo";
  version = "0.14.0";

  src = fetchFromGitHub {
    owner = "getpaseo";
    repo = "paseo";
    tag = "v${finalAttrs.version}";
    hash = "sha256-gtmTf6gbCczT18jk4ZYrNhcW3b6it1yVCnvZqa6gOsA=";
  };

  nodejs = nodejs_22;

  npmDepsHash = "sha256-uIw3h6ObE0ojmKDFzZlNJjGyxHUPYXN0xKLjlcrrIws=";
  npmDepsFetcherVersion = 2;

  # Skip dependency install scripts that download binaries outside the sandbox.
  # Apply the monorepo patches and rebuild only node-pty explicitly below.
  npmRebuildFlags = [ "--ignore-scripts" ];

  nativeBuildInputs = [
    python3
    makeWrapper
  ]
  ++ lib.optionals stdenv.hostPlatform.isLinux [ formatelf ];

  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [
    libuv
    stdenv.cc.cc.lib
  ];

  dontNpmBuild = true;

  buildPhase = ''
    runHook preBuild

    npm run postinstall
    npm_config_build_from_source=true npm_config_nodedir=${finalAttrs.nodejs} \
      npm rebuild node-pty --workspace @getpaseo/server

    # Headless daemon and CLI; browser clients are supplied separately.
    npm run build:server

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    # Upstream traces the daemon, CLI, workers, native addons and runtime assets.
    mkdir -p "$out/libexec/paseo"
    node scripts/trace-daemon.mjs > daemon-files.txt
    while IFS= read -r path; do
      [ -z "$path" ] && continue
      mkdir -p "$out/libexec/paseo/$(dirname "$path")"
      cp -a "$path" "$out/libexec/paseo/$path"
    done < daemon-files.txt

    cp package.json "$out/libexec/paseo/"

    # Terminal shell hooks execute the retained CLI without a system Node.
    patchShebangs --build "$out/libexec/paseo"

    mkdir -p "$out/bin"
    makeWrapper ${finalAttrs.nodejs}/bin/node "$out/bin/paseo-server" \
      --add-flags "$out/libexec/paseo/packages/server/dist/scripts/supervisor-entrypoint.js" \
      --set PASEO_NODE_ENV production
    makeWrapper ${finalAttrs.nodejs}/bin/node "$out/bin/paseo" \
      --add-flags "$out/libexec/paseo/packages/cli/dist/index.js" \
      --set NODE_PATH "$out/libexec/paseo/node_modules"

    runHook postInstall
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [
    versionCheckHook
    versionCheckHomeHook
  ];

  passthru.category = "Workflow & Project Management";

  meta = {
    description = "Self-hosted daemon and CLI for orchestrating coding agents";
    homepage = "https://paseo.sh";
    changelog = "https://github.com/getpaseo/paseo/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.asl20;
    sourceProvenance = [ lib.sourceTypes.fromSource ];
    maintainers = with flake.lib.maintainers; [ sleroq ];
    mainProgram = "paseo";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
      "aarch64-darwin"
    ];
  };
})
