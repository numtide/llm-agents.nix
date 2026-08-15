{
  lib,
  flake,
  stdenv,
  rustPlatform,
  fetchFromGitHub,
  fetchPnpmDeps,
  pnpmConfigHook,
  pnpm_10,
  fetchurl,
  nodejs_24,
  codex,
  codex-acp,
  gemini-cli,
  cargo-tauri,
  pkg-config,
  wrapGAppsHook3,
  makeBinaryWrapper,
  rcodesign,
  glib-networking,
  openssl,
  webkitgtk_4_1,
  kandev,
  git,
  bash,
  openssh,
}:

let
  pnpm = pnpm_10.overrideAttrs (_: {
    version = "9.15.9";
    src = fetchurl {
      url = "https://registry.npmjs.org/pnpm/-/pnpm-9.15.9.tgz";
      hash = "sha256-z4anrXZEBjldQoam0J1zBxFyCsxtk+nc6ax6xNxKKKc=";
    };
  });
in
rustPlatform.buildRustPackage (finalAttrs: {
  pname = "kandev-desktop";
  version = "0.88.0";

  src = fetchFromGitHub {
    owner = "kdlbs";
    repo = "kandev";
    tag = "v${finalAttrs.version}";
    hash = "sha256-YLJ6shH/CCh7I8412Fw6tVuma4bCiBFheH9BDM49T1k=";
  };

  cargoRoot = "apps/desktop/src-tauri";
  buildAndTestSubdir = finalAttrs.cargoRoot;
  cargoHash = "sha256-m/Z92VC/qD47r870CItenXAmaOxC9QBEnLP6wsXZsow=";

  pnpmRoot = "apps";
  pnpmDeps = fetchPnpmDeps {
    inherit (finalAttrs) pname version src;
    sourceRoot = "${finalAttrs.src.name}/apps";
    inherit pnpm;
    fetcherVersion = 4;
    hash = "sha256-5GBYP7Ryr7RkIzxTsc15y1squza74KwgyS39rtfJPq0=";
  };

  nativeBuildInputs = [
    cargo-tauri.hook
    nodejs_24
    pnpm
    pnpmConfigHook
  ]
  ++ lib.optionals stdenv.hostPlatform.isLinux [
    pkg-config
    wrapGAppsHook3
  ]
  ++ lib.optionals stdenv.hostPlatform.isDarwin [
    makeBinaryWrapper
    rcodesign
  ];

  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [
    glib-networking
    openssl
    webkitgtk_4_1
  ];

  buildFeatures = [ "desktop-runtime" ];
  doCheck = false;

  postPatch = ''
    # The package has a second helper binary. Tauri otherwise bundles that
    # binary instead of the feature-gated desktop application.
    substituteInPlace apps/desktop/src-tauri/Cargo.toml \
      --replace-fail '[package]' $'[package]\ndefault-run = "kandev-desktop"'

    # Nix owns upgrades. Keep release discovery, but never replace the running
    # immutable application with an upstream installer.
    substituteInPlace apps/desktop/src-tauri/src/updater.rs \
      --replace-fail \
        'UpdatePlatform::MacOs | UpdatePlatform::Windows => InstallSupport::supported(),' \
        'UpdatePlatform::MacOs | UpdatePlatform::Windows => InstallSupport::unsupported("Update Kandev through Nix."),'
  '';

  preBuild = ''
    if [[ ${kandev.version} != ${finalAttrs.version} ]]; then
      echo "Kandev Desktop ${finalAttrs.version} requires the matching Kandev runtime; got ${kandev.version}." >&2
      exit 1
    fi

    runtime=apps/desktop/src-tauri/resources/kandev
    rm -rf "$runtime"
    mkdir -p "$runtime/bin"
    cp -L ${kandev}/libexec/kandev/bin/* "$runtime/bin/"
    chmod +x "$runtime/bin/"*
  '';

  dontStrip = true;
  dontPatchELF = true;

  preFixup = lib.optionalString stdenv.hostPlatform.isLinux ''
    gappsWrapperArgs+=(
      --prefix PATH : ${
        lib.makeBinPath [
          nodejs_24
          codex
          codex-acp
          gemini-cli
          git
          bash
          openssh
        ]
      }
    )
  '';

  postInstall = lib.optionalString stdenv.hostPlatform.isDarwin ''
    app="$out/Applications/Kandev.app"
    launcher="$app/Contents/MacOS/kandev-desktop"
    mv "$launcher" "$launcher-unwrapped"
    makeBinaryWrapper \
      "$launcher-unwrapped" \
      "$launcher" \
      --prefix PATH : ${
        lib.makeBinPath [
          nodejs_24
          codex
          codex-acp
          gemini-cli
          git
          bash
          openssh
        ]
      }
    mkdir -p "$out/bin"
    ln -s "$launcher" "$out/bin/kandev-desktop"
  '';

  postFixup = lib.optionalString stdenv.hostPlatform.isDarwin ''
    app="$out/Applications/Kandev.app"
    ${lib.getExe rcodesign} sign --code-signature-flags linker-signed \
      "$app/Contents/Resources/kandev/bin/agentctl-darwin-arm64"
    ${lib.getExe rcodesign} sign --code-signature-flags linker-signed \
      "$app/Contents/Resources/kandev/bin/agentctl-darwin-amd64"
    ${lib.getExe rcodesign} sign --code-signature-flags linker-signed \
      "$app/Contents/MacOS/kandev-desktop-unwrapped"
    ${lib.getExe rcodesign} sign --code-signature-flags linker-signed \
      "$app/Contents/MacOS/kandev-desktop"
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck

    test -x "$out/bin/kandev-desktop"
    grep -aF '${nodejs_24}/bin' "$out/bin/kandev-desktop" >/dev/null
    runtime=$out/${
      if stdenv.hostPlatform.isDarwin then "Applications/Kandev.app/Contents/Resources" else "lib/Kandev"
    }/kandev
    test -x "$runtime/bin/kandev"
    test -x "$runtime/bin/agentctl"
    for helper in \
      agentctl-linux-amd64 \
      agentctl-linux-arm64 \
      agentctl-darwin-arm64 \
      agentctl-darwin-amd64
    do
      test -x "$runtime/bin/$helper"
    done

    runHook postInstallCheck
  '';

  passthru.category = "Workflow & Project Management";

  meta = {
    description = "Native desktop application for the Kandev agentic development platform";
    homepage = "https://github.com/kdlbs/kandev";
    changelog = "https://github.com/kdlbs/kandev/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.agpl3Only;
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
    maintainers = with flake.lib.maintainers; [ mulatta ];
    mainProgram = "kandev-desktop";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
      "aarch64-darwin"
    ];
  };
})
