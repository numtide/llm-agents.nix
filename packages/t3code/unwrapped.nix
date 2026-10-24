{
  lib,
  flake,
  stdenv,
  fetchFromGitHub,
  fetchPnpmDeps,
  pnpm_11,
  pnpmConfigHook,
  pnpmBuildHook,
  nodejs_24,
  node-gyp,
  pkg-config,
  formatelf,
  libsecret,
  python3,
  cacert,
  electron_44,
  makeBinaryWrapper,
  installShellFiles,
  makeDesktopItem,
  rustPlatform,
  versionCheckHook,
  versionCheckHomeHook,
  cctools,
  libicns,
  writeDarwinBundle,
  xcbuild,
}:

let
  pname = "t3code";
  version = "0.1.2";
  pnpm = pnpm_11;

  src = fetchFromGitHub {
    owner = "pingdotgg";
    repo = "t3code";
    tag = "v${version}";
    hash = "sha256-C5l7541kanlsukhswrAEu8GFpr/YpWDnofJ5dlg7+LM=";
  };

  # The web build's third-party-licenses vite plugin downloads SPDX license
  # texts unless they are already cached under .generated/. Keep rev in sync
  # with SPDX_LICENSE_LIST_REVISION in scripts/lib/third-party-licenses.ts.
  spdxLicenses = fetchFromGitHub {
    owner = "spdx";
    repo = "license-list-data";
    rev = "c4a7237ec8f4654e867546f9f409749300f1bf4c";
    sparseCheckout = [ "json/details" ];
    hash = "sha256-DnrdJ13M8Vf8Dq8qKlO7Ad5jXa8L9YU9PBlpp7B9BoI=";
  };

  resourceMonitor = rustPlatform.buildRustPackage {
    pname = "t3code-resource-monitor";
    inherit version src;

    sourceRoot = "${src.name}/native/resource-monitor";
    # inspects the test process's own RSS via procfs, 0 on some builders
    checkFlags = [ "--skip=tests::loads_details_when_an_existing_process_becomes_selected" ];
    cargoHash = "sha256-5cmG2daM1bVOA23gjjoalbx0fEL1hmqV6WZov0sUZp8=";
  };

  platformKey =
    {
      x86_64-linux = "linux-x64";
      aarch64-linux = "linux-arm64";
      aarch64-darwin = "darwin-arm64";
    }
    .${stdenv.hostPlatform.system};

  pnpmWorkspaces = [
    "@t3tools/monorepo"
    "t3..."
    "@t3tools/desktop..."
    "@t3tools/scripts..."
  ];

  appName = "T3 Code (Beta)";
  desktopIcon =
    if stdenv.hostPlatform.isDarwin then
      "assets/prod/black-macos-1024.png"
    else
      "assets/prod/black-universal-1024.png";

  desktopItem = makeDesktopItem {
    name = "t3code";
    desktopName = appName;
    comment = "Control surface for coding agents";
    exec = "t3code-desktop %U";
    icon = "t3code";
    categories = [ "Development" ];
    startupWMClass = "t3code";
  };
in
stdenv.mkDerivation {
  inherit
    pname
    version
    src
    pnpmWorkspaces
    ;

  outputs = [
    "out"
    "desktop"
  ];

  strictDeps = true;
  __structuredAttrs = true;

  # Public production identifiers, also embedded in upstream release builds.
  # loadRepoEnv supplies the corresponding VITE_* values for the web frontend.
  env = {
    T3CODE_RELAY_URL = "https://relay.t3.codes";
    T3CODE_CLERK_PUBLISHABLE_KEY = "pk_live_Y2xlcmsudDMuY29kZXMk";
    T3CODE_CLERK_CLI_OAUTH_CLIENT_ID = "hzxSgY2cH10sDU2r";
  };

  pnpmDeps = fetchPnpmDeps {
    inherit
      pnpm
      pname
      version
      src
      pnpmWorkspaces
      ;
    fetcherVersion = 4;
    hash = "sha256-xRmOrOZbBljaF1IJr0JFUFzdhkld6+ehLIlpVOg/J3E=";
  };

  nativeBuildInputs = [
    cacert
    installShellFiles
    makeBinaryWrapper
    node-gyp
    nodejs_24
    pnpm
    pnpmBuildHook
    pnpmConfigHook
    python3
  ]
  ++ lib.optionals stdenv.hostPlatform.isLinux [
    formatelf
    pkg-config
  ]
  ++ lib.optionals stdenv.hostPlatform.isDarwin [
    cctools.libtool
    libicns
    writeDarwinBundle
    xcbuild
  ];

  # build:desktop compiles native/browser-secret against libsecret on linux
  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [
    libsecret
    stdenv.cc.cc.lib
  ];

  # We run electron on an unpacked tree, so app.isPackaged is false and the
  # backend would treat the store path as the workspace root (#9182).
  postPatch = ''
    substituteInPlace apps/desktop/src/app/DesktopEnvironment.ts \
      --replace-fail "backendCwd: input.isPackaged ? homeDirectory : appRoot," "backendCwd: homeDirectory,"

    spdxRev=$(sed -n 's/^const SPDX_LICENSE_LIST_REVISION = "\(.*\)";/\1/p' scripts/lib/third-party-licenses.ts)
    if [[ "$spdxRev" != "${spdxLicenses.rev}" ]]; then
      echo "error: upstream pins SPDX license-list-data $spdxRev, update spdxLicenses" >&2
      exit 1
    fi
    spdxVer=$(sed -n 's/^const SPDX_LICENSE_LIST_VERSION = "\(.*\)";/\1/p' scripts/lib/third-party-licenses.ts)
    mkdir -p .generated/third-party-licenses/spdx
    ln -s ${spdxLicenses}/json/details ".generated/third-party-licenses/spdx/$spdxVer"
  '';

  preBuild = ''
    export pnpm_config_verify_deps_before_run=false

    node scripts/update-release-package-versions.ts ${version}

    upstream_electron=$(node -p "require('./apps/desktop/package.json').dependencies.electron")
    upstream_major=''${upstream_electron#^}
    upstream_major=''${upstream_major%%.*}
    nix_major=${lib.versions.major electron_44.version}
    if (( upstream_major > nix_major )); then
      echo "error: upstream expects Electron $upstream_electron but nixpkgs provides ${electron_44.version}" >&2
      exit 1
    fi

    export npm_config_nodedir=${nodejs_24}
    export ELECTRON_SKIP_BINARY_DOWNLOAD=1
    pnpm rebuild --pending "''${pnpmInstallFlags[@]}" \
      --filter '!@t3tools/monorepo'
  '';

  pnpmBuildScript = "build:desktop";

  # Dependencies include prebuilt artifacts for foreign systems and statically
  # linked executables, which must not be patched or audited as host binaries.
  dontPatchELF = true;
  dontAutoPatchelf = true;
  noAuditTmpdir = true;

  installPhase = ''
    runHook preInstall

    # Deploy isolated production graphs instead of the whole workspace store.
    pnpm --filter t3 deploy --prod --offline "$out/libexec/t3code/apps/server"

    mkdir -p "$out/libexec/t3code/apps/server/dist/resource-monitor/${platformKey}"
    install -Dm755 ${resourceMonitor}/bin/t3-resource-monitor \
      "$out/libexec/t3code/apps/server/dist/resource-monitor/${platformKey}/t3-resource-monitor"

    mkdir -p "$out/bin"
    makeWrapper ${lib.getExe nodejs_24} "$out/bin/t3" \
      --add-flags "$out/libexec/t3code/apps/server/dist/bin.mjs"

    pnpm --filter @t3tools/desktop deploy --prod --offline "$desktop/libexec/t3code/apps/desktop"
    cp -r --no-preserve=mode apps/desktop/dist-electron "$desktop/libexec/t3code/apps/desktop/"
    mkdir -p "$desktop/libexec/t3code/apps/desktop/prod-resources"
    install -Dm444 ${desktopIcon} \
      "$desktop/libexec/t3code/apps/desktop/prod-resources/icon.png"

    ln -s "$out/libexec/t3code/apps/server" "$desktop/libexec/t3code/apps/server"

    mkdir -p "$desktop/libexec/t3code/apps/desktop/prod-resources/resource-monitor"
    ln -s \
      "$out/libexec/t3code/apps/server/dist/resource-monitor/${platformKey}/t3-resource-monitor" \
      "$desktop/libexec/t3code/apps/desktop/prod-resources/resource-monitor/t3-resource-monitor"

    ${lib.optionalString stdenv.hostPlatform.isLinux ''
      install -Dm755 native/browser-secret/build/${stdenv.hostPlatform.node.arch}/t3-browser-secret \
        "$desktop/libexec/t3code/apps/desktop/prod-resources/browser-secret/t3-browser-secret"
    ''}

    find "$out/libexec/t3code" "$desktop/libexec/t3code" -xtype l -delete

    mkdir -p "$desktop/bin"
    makeWrapper ${lib.getExe electron_44} "$desktop/bin/t3code-desktop" \
      --add-flags "$desktop/libexec/t3code/apps/desktop" \
      --inherit-argv0

    mkdir -p "$desktop/share/icons/hicolor/scalable/apps"
    install -Dm444 ${desktopIcon} "$desktop/share/icons/t3code.png"
    install -Dm444 assets/prod/logo.svg "$desktop/share/icons/hicolor/scalable/apps/t3code.svg"
    cp -r ${desktopItem}/share/applications "$desktop/share/"

    ${lib.optionalString stdenv.hostPlatform.isDarwin ''
      find "$out/libexec/t3code" "$desktop/libexec/t3code" \
        -path '*/node-pty/prebuilds/darwin-*/spawn-helper' \
        -exec chmod 755 {} +

      mkdir -p "$desktop/Applications/${appName}.app/Contents/"{MacOS,Resources}
      png2icns \
        "$desktop/Applications/${appName}.app/Contents/Resources/t3code.icns" \
        ${desktopIcon}
      ${stdenv.shell} ${lib.getExe writeDarwinBundle} \
        "$desktop" "${appName}" t3code-desktop t3code
    ''}

    runHook postInstall
  '';

  # Electron, unlike node, does not already have libstdc++ loaded for the
  # prebuilt pty.node (#10125).
  postFixup = lib.optionalString stdenv.hostPlatform.isLinux ''
    autoPatchelf "$out/libexec/t3code/apps/server/node_modules/node-pty/prebuilds/${platformKey}"
  '';

  postInstall = ''
    for shell in bash fish zsh; do
      installShellCompletion --cmd t3 --"$shell" <("$out/bin/t3" --completions "$shell")
    done
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [
    versionCheckHook
    versionCheckHomeHook
  ];
  versionCheckProgramArg = [ "--version" ];

  passthru = {
    category = "AI Coding Agents";
    inherit appName resourceMonitor;
  };

  meta = {
    description = "Control surface for coding agents";
    homepage = "https://t3.codes";
    changelog = "https://github.com/pingdotgg/t3code/releases/tag/v${version}";
    license = lib.licenses.mit;
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
    maintainers = with flake.lib.maintainers; [ dancodes ];
    mainProgram = "t3";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
      "aarch64-darwin"
    ];
  };
}
