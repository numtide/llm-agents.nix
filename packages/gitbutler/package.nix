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
  # pnpm 11+ needs fetcherVersion >= 4 and a different pnpmDeps hash
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

  # pnpm stores only the fetching host's node for `devEngines.runtime`, which
  # makes the pnpmDeps hash platform-dependent. We build with nixpkgs' nodejs.
  # Replace with pnpm's `runtime: false` once nixpkgs ships pnpm >= 12.16.
  stripNodeRuntime = ''
    ${lib.getExe jq} -e '.devEngines.runtime' package.json >/dev/null
    grep -q '^  node@runtime:' pnpm-lock.yaml
    ${lib.getExe jq} 'del(.devEngines.runtime)' package.json > package.json.tmp
    mv package.json.tmp package.json
    sed -i -e '/^  node@runtime:/,/^$/d' \
      -e '/^      node:$/{N;/specifier: runtime:/{N;d}}' pnpm-lock.yaml
    if grep -Eq 'node@runtime|specifier: runtime:' pnpm-lock.yaml; then
      echo "node runtime still referenced after stripping" >&2
      exit 1
    fi
  '';
in

rustPlatform.buildRustPackage (finalAttrs: {
  pname = "gitbutler";
  version = "0.23.2";

  src = fetchFromGitHub {
    owner = "gitbutlerapp";
    repo = "gitbutler";
    tag = "release/${finalAttrs.version}";
    hash = "sha256-JLsIlkbNRqjCgidgI33djWcseGkwsEBzw6g9q6eYoDg=";
  };

  # Pin the user-facing version into the Tauri release config and disable the
  # built-in updater so the packaged app doesn't try to self-update. The
  # `externalBin` rewrite keeps only the git helper shims that we actually ship.
  postPatch = ''
    ${stripNodeRuntime}

    # nixpkgs' rustc uses LLVM 21, whose vpdpbusd.256 signature does not match
    # core::arch's; drop adler32furious' VNNI kernels until rustc uses LLVM 22.
    patch -p1 -d "$cargoDepsCopy/source-registry-0/adler32furious-0.1.1" < ${./adler32furious-llvm21.patch}

    tauriConfRelease="crates/gitbutler-tauri/tauri.conf.release.json"
    jq '.
        | (.version = "${finalAttrs.version}")
        | (.bundle.createUpdaterArtifacts = false)
        | (.bundle.externalBin = ["gitbutler-git-askpass"])
      ' "$tauriConfRelease" | sponge "$tauriConfRelease"

    substituteInPlace apps/desktop/src/lib/backend/tauri.ts \
      --replace-fail 'checkUpdate = tauriCheck;' 'checkUpdate = () => null;'

  '';

  cargoHash = "sha256-Q+or42ppjjkt4OEc+cC2knTCkB7XloePpt2beHYG4q4=";

  pnpmDeps = fetchPnpmDeps {
    inherit (finalAttrs) pname version src;
    inherit pnpm;
    fetcherVersion = 3;
    postPatch = stripNodeRuntime;
    hash = "sha256-waNmBkrMFkp/Wtai8OGFqX8d0b8N542bOCJ0HLUHPRk=";
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
    # Read via option_env! to pick the app identifier/data dir. Unset means dev build.
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
