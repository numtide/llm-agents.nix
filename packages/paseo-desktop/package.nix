# Vendored from upstream's own from-source nix expression:
#   https://github.com/getpaseo/paseo/blob/v0.1.85/nix/desktop-package.nix
#
# Adaptations for this repo:
#   - src: fetchFromGitHub of the release tag instead of `cleanSourceWith ./..`
#     (the source filter is unnecessary for a fetched tarball).
#   - version: pinned explicitly (upstream reads ../package.json at eval time).
#   - npmDeps: built from npmDepsHash with npmDepsFetcherVersion = 2 (repo
#     convention) instead of reusing the daemon package's FOD.
#   - electron: pinned to electron_41 to match upstream's devDependency (41.x).
#   - meta/passthru: this repo's maintainer and category conventions.
#   - installPhase: instead of copying the whole monorepo (packages/ +
#     node_modules/, ~1.3 GB with all devDependencies), reuse upstream's
#     @vercel/nft runtime tracer (scripts/trace-daemon.mjs, also used by their
#     daemon package) plus a supplemental trace of the Electron entry points
#     to ship only the files loaded at runtime.
#   - node-pty: delete the bundled manylinux prebuilds before `npm rebuild` so
#     node-gyp-build actually compiles it against nix libraries. The prebuilt
#     pty.node has no rpath and needs a system libstdc++.so.6, which fails to
#     dlopen on NixOS and silently breaks the terminal feature.
{
  lib,
  stdenv,
  flake,
  buildNpmPackage,
  fetchFromGitHub,
  nodejs_22,
  python3,
  makeWrapper,
  copyDesktopItems,
  makeDesktopItem,
  electron_41,
  libuv,
  formatelf,
  gcc-unwrapped,
}:

buildNpmPackage (finalAttrs: {
  pname = "paseo-desktop";
  version = "0.3.0";

  src = fetchFromGitHub {
    owner = "getpaseo";
    repo = "paseo";
    tag = "v${finalAttrs.version}";
    hash = "sha256-6LPCDohpd7tPz3e6iAyhL+MUljIfiBucUw93c0R/mjY=";
  };

  nodejs = nodejs_22;

  npmDepsHash = "sha256-CbdP7eAcN/dRhwIv3sqxjCRirRNAjeOOJchNfpSS6U0=";
  npmDepsFetcherVersion = 2;

  # Prevent onnxruntime-node's install script from running during automatic
  # npm rebuild. We manually rebuild only node-pty in buildPhase.
  npmRebuildFlags = [ "--ignore-scripts" ];

  nativeBuildInputs = [
    python3 # for node-gyp (node-pty)
    makeWrapper
    copyDesktopItems
    formatelf
  ];

  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [
    libuv
    gcc-unwrapped.lib
  ];

  dontNpmBuild = true;

  env = {
    EXPO_NO_TELEMETRY = "1";
    # Expo's web build pulls in some pre-bundled assets; ensure it doesn't try
    # to phone home during the build.
    CI = "1";
  };

  buildPhase = ''
    runHook preBuild

    # Native deps (terminal emulation; libuv-linked on Linux).
    # node-gyp-build skips compilation when a matching prebuilt binary exists,
    # so remove the bundled prebuilds first to force a real build.
    rm -rf node_modules/node-pty/prebuilds
    npm rebuild node-pty

    # Server workspaces (highlight + relay + protocol + client + server + cli)
    npm run build:server

    # App workspace deps not covered by build:server
    npm run build --workspace=@getpaseo/expo-two-way-audio

    # Expo web export for the Electron renderer
    ( cd packages/app && PASEO_WEB_PLATFORM=electron npx expo export --platform web )

    # Desktop main process (tsc only — NOT electron-builder)
    npm run build:main --workspace=@getpaseo/desktop

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/share/paseo-desktop $out/bin

    # Compute the runtime file closure:
    #  - upstream's tracer covers the daemon + CLI (spawned by the desktop
    #    app's daemon-manager via @getpaseo/server and @getpaseo/cli);
    #  - a supplemental @vercel/nft trace covers the Electron main/preload
    #    entry points and the CLI passthrough module (dist/run.js) that the
    #    desktop app imports at runtime.
    node scripts/trace-daemon.mjs > runtime-files.txt
    node --input-type=module -e '
      import { nodeFileTrace } from "@vercel/nft";
      const { fileList } = await nodeFileTrace(
        [
          "packages/desktop/dist/main.js",
          "packages/desktop/dist/preload.js",
          "node_modules/@getpaseo/cli/dist/run.js",
        ],
        {
          base: process.cwd(),
          ignore: ["**/*.test.js", "**/*.e2e.test.js"],
        },
      );
      for (const f of [...fileList].sort()) console.log(f);
    ' >> runtime-files.txt

    # Files read via fs APIs rather than require(): the pre-exported Expo web
    # renderer (served through the paseo:// protocol handler), desktop assets
    # (window icons), and the agent skills directory.
    {
      find packages/app/dist -type f
      echo packages/app/package.json
      find packages/desktop/assets -type f
      echo packages/desktop/package.json
      # node-pty's compiled addon: loaded via a runtime-computed path that
      # static tracing cannot follow (build/Release is checked first).
      find node_modules/node-pty/build/Release -maxdepth 1 -type f
      if [ -d skills ]; then find skills -type f; fi
      # Root package.json lets node resolve the workspace layout.
      echo package.json
    } >> runtime-files.txt

    # Materialize the traced closure, preserving directory structure and the
    # node_modules/@getpaseo/* workspace symlinks (tar archives symlinks
    # as-is, which node's module resolution requires).
    sort -u runtime-files.txt | tar cf - --no-recursion -T - \
      | tar xf - -C $out/share/paseo-desktop

    # Hicolor icon for desktop environments
    install -Dm644 packages/desktop/assets/icon.png \
      $out/share/icons/hicolor/512x512/apps/paseo-desktop.png

    # Launcher wraps nixpkgs electron.
    # --no-sandbox: Chromium's setuid sandbox can't live in /nix/store
    # (immutable, no setuid).
    #
    # EXPO_DEV_URL: We run unpackaged via `electron path/to/main.js`, so
    # `app.isPackaged` is false. In that mode main.ts loads `DEV_SERVER_URL`
    # (defaults to http://localhost:8081 — the Expo dev server, which doesn't
    # exist here). Point it at the `paseo://` protocol handler instead, which
    # serves from `__dirname/../../app/dist` (our install layout matches).
    makeWrapper ${electron_41}/bin/electron $out/bin/paseo-desktop \
      --add-flags "$out/share/paseo-desktop/packages/desktop/dist/main.js" \
      --add-flags "--no-sandbox" \
      --set EXPO_DEV_URL "paseo://app/"

    copyDesktopItems

    runHook postInstall
  '';

  desktopItems = [
    (makeDesktopItem {
      name = "paseo-desktop";
      desktopName = "Paseo";
      genericName = "AI Coding Agents";
      comment = "Self-hosted daemon for AI coding agents";
      exec = "paseo-desktop";
      icon = "paseo-desktop";
      categories = [ "Development" ];
      startupWMClass = "Paseo";
    })
  ];

  passthru.category = "Voice & Transcription";

  meta = {
    description = "Voice-controlled desktop development environment for AI coding agents";
    homepage = "https://paseo.sh";
    changelog = "https://github.com/getpaseo/paseo/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.agpl3Plus;
    sourceProvenance = [ lib.sourceTypes.fromSource ];
    maintainers = with flake.lib.maintainers; [ smdex ];
    mainProgram = "paseo-desktop";
    platforms = lib.platforms.linux;
  };
})
