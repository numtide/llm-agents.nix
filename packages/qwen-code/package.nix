{
  lib,
  stdenv,
  buildNpmPackage,
  fetchFromGitHub,
  fetchPnpmDeps,
  pnpm_11,
  pnpmConfigHook,
  git,
  ripgrep,
  pkg-config,
  glib,
  libsecret,
  darwinOpenptyHook,
  clang_20,
  versionCheckHook,
}:

buildNpmPackage (finalAttrs: {
  pname = "qwen-code";
  version = "0.26.5";

  src = fetchFromGitHub {
    owner = "QwenLM";
    repo = "qwen-code";
    tag = "v${finalAttrs.version}";
    hash = "sha256-N/hMDkMdFybxsFrHpmMBKcSyIK5nx0EzXlKG4fFm5XM=";
  };

  npmDeps = null;
  pnpmDeps = fetchPnpmDeps {
    inherit (finalAttrs) pname version src;
    pnpm = pnpm_11;
    fetcherVersion = 4;
    hash = "sha256-Zq9uFXaDxajcHz/E0KH0lmmxgnGilVQgA/WtAYi+XlA=";
  };
  npmConfigHook = pnpmConfigHook;
  dontNpmPrune = true;

  nativeBuildInputs = [
    pnpm_11
    pkg-config
    git
  ]
  ++ lib.optionals stdenv.hostPlatform.isDarwin [
    clang_20 # Works around node-addon-api constant expression issue with clang 21+ (keytar)
    darwinOpenptyHook # Fixes node-pty openpty/forkpty build issue
  ];

  buildInputs = [
    ripgrep
    glib
    libsecret
  ];

  # corepack would download the pnpm version pinned upstream at build time.
  postPatch = ''
    substituteInPlace scripts/build.js --replace-fail "corepack pnpm" pnpm
  '';

  buildPhase = ''
    runHook preBuild

    # Upstream's postinstall applies patches/ink+*.patch, which adds the
    # selection props the CLI uses. Install scripts are skipped here.
    node_modules/.bin/patch-package

    # npmConfigHook only patches the root node_modules. Workspaces with
    # nested .bin (web-shell's vite) keep /usr/bin/env otherwise.
    patchShebangs packages/*/node_modules

    npm run generate
    # The CLI esbuild bundle resolves imports against workspace dist/ output.
    # Use upstream's --cli-only build order so every workspace the bundle pulls
    # in (core, channels, acp-bridge, sdk-typescript, ...) is built, without
    # us having to track the dependency list by hand across releases.
    node scripts/build.js --cli-only
    npm run bundle

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin $out/share/qwen-code
    cp -r dist/* $out/share/qwen-code/
    # The bundled dist/cli.js has no shebang; upstream ships a bin wrapper
    # (scripts/cli-entry.js) that relaunches cli.js with node --expose-gc and
    # reads package.json for the reported version. Install both next to cli.js.
    cp scripts/cli-entry.js $out/share/qwen-code/cli-entry.js
    cp package.json $out/share/qwen-code/package.json
    # Install production dependencies only
    CI=true pnpm prune --prod --ignore-scripts
    cp -r node_modules $out/share/qwen-code/
    # Remove broken symlinks that cause issues in Nix environment
    find $out/share/qwen-code/node_modules -type l -delete || true
    patchShebangs $out/share/qwen-code
    ln -s $out/share/qwen-code/cli-entry.js $out/bin/qwen

    runHook postInstall
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [ versionCheckHook ];

  passthru.category = "AI Coding Agents";

  meta = {
    description = "Command-line AI workflow tool for Qwen3-Coder models";
    homepage = "https://github.com/QwenLM/qwen-code";
    changelog = "https://github.com/QwenLM/qwen-code/releases";
    license = lib.licenses.asl20;
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
    maintainers = with lib.maintainers; [
      zimbatm
      lonerOrz
    ];
    platforms = lib.platforms.all;
    mainProgram = "qwen";
  };
})
