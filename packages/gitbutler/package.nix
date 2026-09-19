{
  lib,
  flake,
  stdenv,
  cacert,
  cargo-tauri,
  cmake,
  curl,
  dart-sass,
  desktop-file-utils,
  fetchFromGitHub,
  fetchPnpmDeps,
  glib-networking,
  jq,
  makeBinaryWrapper,
  moreutils,
  nodejs,
  openssl,
  pkg-config,
  # Lockfile predates pnpm 11's stricter overrides validation
  pnpm_10,
  pnpmConfigHook,
  rust,
  rustPlatform,
  turbo,
  webkitgtk_4_1,
  wrapGAppsHook4,
  unpinCargoMsrvHook,
}:
let
  pnpm = pnpm_10;
in

rustPlatform.buildRustPackage (finalAttrs: {
  pname = "gitbutler";
  version = "0.22.3";

  src = fetchFromGitHub {
    owner = "gitbutlerapp";
    repo = "gitbutler";
    tag = "release/${finalAttrs.version}";
    hash = "sha256-nW3yCbpbIhawLQVV+DptzGYiFBSKcyAP89NtDWHJM+0=";
  };

  # Pin the user-facing version into the Tauri release config and disable the
  # built-in updater so the packaged app doesn't try to self-update. The
  # `externalBin` rewrite keeps only the git helper shims that we actually ship.
  postPatch = ''
    tauriConfRelease="crates/gitbutler-tauri/tauri.conf.release.json"
    jq '.
        | (.version = "${finalAttrs.version}")
        | (.bundle.createUpdaterArtifacts = false)
        | (.bundle.externalBin = ["gitbutler-git-askpass"])
      ' "$tauriConfRelease" | sponge "$tauriConfRelease"

    substituteInPlace apps/desktop/src/lib/backend/tauri.ts \
      --replace-fail 'checkUpdate = tauriCheck;' 'checkUpdate = () => null;'

  '';

  cargoHash = "sha256-XRc2yok9K7f/vRAqgO78JUq/U36XSiUeOINupfOOSjw=";

  pnpmDeps = fetchPnpmDeps {
    inherit (finalAttrs) pname version src;
    inherit pnpm;
    fetcherVersion = 3;
    hash = "sha256-CZZOZ+ox4kE5hq/W82UrpJ4I9al9TFBiN+K4XUhxnDE=";
  };

  nativeBuildInputs = [
    unpinCargoMsrvHook
    cacert # required by turbo
    cargo-tauri.hook
    cmake # required by the `zlib-sys` crate
    dart-sass
    desktop-file-utils
    jq
    moreutils
    nodejs
    pkg-config
    pnpm
    pnpmConfigHook
    turbo
    wrapGAppsHook4
  ]
  ++ lib.optional stdenv.hostPlatform.isDarwin makeBinaryWrapper;

  buildInputs = [
    openssl
  ]
  ++ lib.optional stdenv.hostPlatform.isDarwin curl
  ++ lib.optionals stdenv.hostPlatform.isLinux [
    glib-networking
    webkitgtk_4_1
  ];

  tauriBuildFlags = [
    "--config"
    "crates/gitbutler-tauri/tauri.conf.release.json"
  ];

  # The workspace test suite requires git fixtures, network access and the
  # full Tauri stack; upstream CI runs these separately.
  doCheck = false;

  env = {
    # Stable GitButler production channel. This must be set at build time so
    # the frontend and backend use the production API/login endpoints.
    CHANNEL = "release";

    # Let `crates/gitbutler-tauri/inject-git-binaries.sh` find the Rust target dir.
    TRIPLE_OVERRIDE = rust.envVars.rustHostPlatformSpec;

    # `fetchPnpmDeps` / `pnpmConfigHook` pin their own pnpm; disable corepack's
    # strict engine check so it doesn't reject that pnpm.
    COREPACK_ENABLE_STRICT = 0;

    # Task tracing requires Tokio built with this cfg.
    RUSTFLAGS = "--cfg tokio_unstable";

    TUBRO_BINARY_PATH = lib.getExe turbo;
    TURBO_TELEMETRY_DISABLED = 1;

    OPENSSL_NO_VENDOR = true;
    # 0.22.0 uses a libgit2-sys fork that requires "libgit2-experimental",
    # which nixpkgs does not provide; build the vendored copy instead.
  };

  preBuild = ''
    # Force the bundled sass-embedded wrapper to invoke our dart-sass binary
    # instead of the prebuilt one it ships with.
    substituteInPlace node_modules/.pnpm/sass-embedded@*/node_modules/sass-embedded/dist/lib/src/compiler-path.js \
      --replace-fail 'compilerCommand = (() => {' 'compilerCommand = (() => { return ["${lib.getExe dart-sass}"];'

    ${lib.getExe turbo} run --filter @gitbutler/svelte-comment-injector build
    pnpm build:desktop -- --mode production
  '';

  postInstall =
    lib.optionalString stdenv.hostPlatform.isDarwin ''
      makeBinaryWrapper $out/Applications/GitButler.app/Contents/MacOS/gitbutler-tauri $out/bin/gitbutler-tauri
    ''
    + lib.optionalString stdenv.hostPlatform.isLinux ''
      desktop-file-edit \
        --set-comment "A Git client for simultaneous branches on top of your existing workflow." \
        --set-key="Keywords" --set-value="git;" \
        --set-key="StartupWMClass" --set-value="GitButler" \
        $out/share/applications/GitButler.desktop
    '';

  passthru.category = "Workflow & Project Management";

  meta = with lib; {
    description = "Git client for simultaneous branches on top of your existing workflow";
    homepage = "https://gitbutler.com";
    changelog = "https://github.com/gitbutlerapp/gitbutler/releases/tag/release/${finalAttrs.version}";
    license = flake.lib.licenses.fsl11Mit;
    sourceProvenance = with sourceTypes; [ fromSource ];
    maintainers = with flake.lib.maintainers; [ mic92 ];
    mainProgram = "gitbutler-tauri";
    platforms = platforms.linux ++ platforms.darwin;
  };
})
