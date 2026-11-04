{
  lib,
  stdenv,
  buildNpmPackage,
  fetchFromGitHub,
  ripgrep,
  pkg-config,
  libsecret,
  darwinOpenptyHook,
  clang_20,
  makeBinaryWrapper,
  versionCheckHook,
  versionCheckHomeHook,
  writeShellScriptBin,
  xsel,
  nodejs,
}:

buildNpmPackage (finalAttrs: {
  npmDepsFetcherVersion = 2;
  pname = "gemini-cli";
  version = "0.67.0";

  src = fetchFromGitHub {
    owner = "google-gemini";
    repo = "gemini-cli";
    tag = "v${finalAttrs.version}";
    hash = "sha256-+jOoJvY3FwDLzCYJq/RD5X81VMecLfGOnw+EnGkZpoM=";
  };

  npmDepsHash = "sha256-sa7va9kRUjs4zFjinX96bLfZnLwjUKeVMOXXR08jqWU=";
  makeCacheWritable = true;

  nativeBuildInputs = [
    pkg-config
    makeBinaryWrapper
  ]
  ++ lib.optionals stdenv.hostPlatform.isDarwin [
    clang_20 # Works around node-addon-api constant expression issue with clang 21+
    darwinOpenptyHook # Fixes node-pty openpty/forkpty build issue
  ];

  dontPatchElf = stdenv.hostPlatform.isDarwin;

  buildInputs = [
    libsecret
  ];

  preConfigure = ''
    mkdir -p packages/generated
    echo "export const GIT_COMMIT_INFO = { commitHash: '${finalAttrs.src.rev}' };" > packages/generated/git-commit.ts
  '';

  postPatch = ''
    # gemini-cli 0.49.0 ships an inconsistent lockfile: several workspace
    # package.json files pin exact dependency versions that differ from the
    # versions package-lock.json actually resolves (e.g. tar 7.5.8 vs 7.5.11,
    # clipboardy 5.2.0 vs 5.2.1). The offline npm cache is built from the
    # lockfile, so `npm ci` cannot satisfy the package.json pins and fails with
    # ETARGET. Rewrite each exact pin to the version the lockfile resolves.
    # Guard on node: postPatch also runs inside the npm-deps fetcher FOD, where
    # node is unavailable. The cache is built from the lockfile (independent of
    # these package.json edits), so skipping the alignment there is harmless;
    # it only needs to run before `npm ci` in the main build.
    if command -v node > /dev/null; then
      node ${./align-pins-to-lock.mjs}
    fi

    # Point resolveRipgrepPath() at our ripgrep: no bundled rg binaries exist
    # and the trusted-path check rejects /nix/store, so allow the store dir.
    substituteInPlace packages/core/src/tools/ripGrep.ts \
      --replace-fail \
        "const systemRg = resolveExecutable('rg');" \
        "const systemRg = resolveExecutable('${lib.getExe ripgrep}');" \
      --replace-fail \
        "if (isTrustedSystemPath(realPath)) {" \
        "if (isTrustedSystemPath(realPath) || realPath.startsWith('${builtins.storeDir}/')) {"

    # Disable auto-update and update nag: Nix manages updates, not the tool itself.
    # v0.27.0 reads these defaults cleanly from the schema (unlike v0.25.2 / nixpkgs#13569).
    sed -i "/enableAutoUpdate: {/,/}/ s/default: true/default: false/" \
      packages/cli/src/config/settingsSchema.ts
    sed -i "/enableAutoUpdateNotification: {/,/}/ s/default: true/default: false/" \
      packages/cli/src/config/settingsSchema.ts
  '';

  # v0.31.0 added @google/gemini-cli-devtools as an implicit workspace
  # dependency of the cli package. npm --workspaces builds packages
  # alphabetically (cli before devtools), so tsc fails to resolve the
  # import. Pre-build devtools so its types are available when cli compiles.
  preBuild = ''
    npm run build --workspace=@google/gemini-cli-devtools
  '';

  # Prevent build-only deps from leaking into the runtime closure
  disallowedReferences = [
    finalAttrs.npmDeps
    nodejs.python
  ];

  installPhase = ''
    runHook preInstall
    mkdir -p $out/{bin,share/gemini-cli}

    npm prune --omit=dev

    cp -r node_modules $out/share/gemini-cli/

    # Replace workspace symlinks with the actual built packages
    for pkg in cli:gemini-cli core:gemini-cli-core a2a-server:gemini-cli-a2a-server \
               devtools:gemini-cli-devtools sdk:gemini-cli-sdk; do
      dir=''${pkg%%:*}
      name=''${pkg##*:}
      rm -f $out/share/gemini-cli/node_modules/@google/"$name"
      cp -r packages/"$dir" $out/share/gemini-cli/node_modules/@google/"$name"
    done
    rm -f $out/share/gemini-cli/node_modules/@google/gemini-cli-test-utils
    rm -f $out/share/gemini-cli/node_modules/gemini-cli-vscode-ide-companion

    # Remove dangling symlinks to source directory
    rm -f $out/share/gemini-cli/node_modules/@google/gemini-cli-core/dist/docs/CONTRIBUTING.md

    makeWrapper ${lib.getExe nodejs} $out/bin/gemini \
      --add-flags "--no-warnings=DEP0040" \
      --add-flags "$out/share/gemini-cli/node_modules/@google/gemini-cli/dist/index.js" \
      ${lib.optionalString stdenv.hostPlatform.isLinux "--prefix PATH : ${lib.makeBinPath [ xsel ]}"}

    # Install JSON schema
    install -Dm644 schemas/settings.schema.json $out/share/gemini-cli/settings.schema.json

    runHook postInstall
  '';

  # Remove files that embed build-time store paths (python shebangs, build
  # artifacts, lockfiles) to satisfy disallowedReferences. Must run in
  # preFixup before patchShebangs rewrites shebangs to Nix store paths.
  preFixup = ''
    find $out/share/gemini-cli/node_modules \
      -name "*.py" -o -name "gyp-mac-tool" \
      -o -name "package-lock.json" -o -name ".package-lock.json" \
      -o -name "config.gypi" \
      -o -path '*/build/*.mk' -o -path '*/build/Makefile' \
      | xargs rm -f
    # @github/keytar/build: keep only the runtime addon. Object files and
    # .deps/*.d embed paths to nodejs-source and -dev outputs, bloating the
    # closure.
    find $out/share/gemini-cli/node_modules/@github/keytar/build \
      -type f -not -name 'keytar.node' -delete
    find $out/share/gemini-cli/node_modules/@github/keytar/build \
      -type d -empty -delete
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [
    versionCheckHook
    versionCheckHomeHook
  ]
  ++ lib.optionals stdenv.hostPlatform.isDarwin [
    # clipboardy → system-architecture calls `sysctl -inq sysctl.proc_translated`
    # at import time to detect Rosetta 2. In the Nix sandbox /usr/sbin/sysctl
    # is absent, causing ENOENT and crashing the version check. Provide a
    # minimal stub that reports "not translated" (exit 0, empty output) so the
    # module resolves the native architecture without pulling in system_cmds.
    (writeShellScriptBin "sysctl" "echo 0")
  ];
  # versionCheckHook runs with --ignore-environment by default, stripping PATH.
  # We need PATH preserved so the sysctl stub (and node itself) can be found
  # by child processes spawned during `gemini --version`.
  versionCheckKeepEnvironment = "PATH";

  passthru = {
    category = "AI Coding Agents";
    jsonschema = "${placeholder "out"}/share/gemini-cli/settings.schema.json";
  };

  meta = {
    description = "AI agent that brings the power of Gemini directly into your terminal";
    homepage = "https://github.com/google-gemini/gemini-cli";
    changelog = "https://github.com/google-gemini/gemini-cli/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.asl20;
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
    platforms = lib.platforms.all;
    mainProgram = "gemini";
  };
})
