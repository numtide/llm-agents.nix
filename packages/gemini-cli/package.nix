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
  fetchNpmDepsWithPackuments,
  npmConfigHook,
  nodejs,
}:

buildNpmPackage (finalAttrs: {
  inherit npmConfigHook;
  pname = "gemini-cli";
  version = "0.29.6";

  src = fetchFromGitHub {
    owner = "google-gemini";
    repo = "gemini-cli";
    tag = "v${finalAttrs.version}";
    hash = "sha256-k9Y497oBvNZGto+ubiGv2kPhPm2E1VwE6UEo6u80WO0=";
  };

  npmDeps = fetchNpmDepsWithPackuments {
    inherit (finalAttrs) src;
    name = "${finalAttrs.pname}-${finalAttrs.version}-npm-deps";
    hash = "sha256-5vJH/5FM7oWc+bWWgps9XNdLen4FabAOYwOKnPa2DMg=";
    fetcherVersion = 2;
  };
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
    # Hardcode ripgrep path so ensureRgPath() returns our Nix-provided binary
    # instead of downloading or finding a dynamically-linked one
    substituteInPlace packages/core/src/tools/ripGrep.ts \
      --replace-fail "await ensureRgPath();" "'${lib.getExe ripgrep}';"

    # Disable auto-update and update nag: Nix manages updates, not the tool itself.
    # v0.27.0 reads these defaults cleanly from the schema (unlike v0.25.2 / nixpkgs#13569).
    sed -i "/enableAutoUpdate: {/,/}/ s/default: true/default: false/" \
      packages/cli/src/config/settingsSchema.ts
    sed -i "/enableAutoUpdateNotification: {/,/}/ s/default: true/default: false/" \
      packages/cli/src/config/settingsSchema.ts
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

    rm -f $out/share/gemini-cli/node_modules/@google/gemini-cli
    rm -f $out/share/gemini-cli/node_modules/@google/gemini-cli-core
    rm -f $out/share/gemini-cli/node_modules/@google/gemini-cli-a2a-server
    rm -f $out/share/gemini-cli/node_modules/@google/gemini-cli-test-utils
    rm -f $out/share/gemini-cli/node_modules/gemini-cli-vscode-ide-companion
    cp -r packages/cli $out/share/gemini-cli/node_modules/@google/gemini-cli
    cp -r packages/core $out/share/gemini-cli/node_modules/@google/gemini-cli-core
    cp -r packages/a2a-server $out/share/gemini-cli/node_modules/@google/gemini-cli-a2a-server

    # Remove dangling symlinks to source directory
    rm -f $out/share/gemini-cli/node_modules/@google/gemini-cli-core/dist/docs/CONTRIBUTING.md

    ln -s $out/share/gemini-cli/node_modules/@google/gemini-cli/dist/index.js $out/bin/gemini
    chmod +x "$out/bin/gemini"

    ${lib.optionalString stdenv.hostPlatform.isLinux ''
      wrapProgram $out/bin/gemini \
        --prefix PATH : ${lib.makeBinPath [ xsel ]}
    ''}

    # Install JSON schema
    install -Dm644 schemas/settings.schema.json $out/share/gemini-cli/settings.schema.json

    runHook postInstall
  '';

  # Clean up files that would create closure references to build-only deps.
  # Must run in preFixup (before patchShebangs patches shebangs to Nix store paths).
  preFixup = ''
    # Remove python files and gyp-mac-tool scripts that have python shebangs
    find $out/share/gemini-cli/node_modules -name "*.py" -delete
    find $out/share/gemini-cli/node_modules -name "gyp-mac-tool" -delete
    # Remove native module build artifacts that reference python/build-time deps.
    # Only the compiled .node files in build/Release/ are needed at runtime.
    rm -rf $out/share/gemini-cli/node_modules/keytar/build
    find $out/share/gemini-cli/node_modules -path '*/build/*.mk' -delete
    find $out/share/gemini-cli/node_modules -path '*/build/Makefile' -delete
    # Remove metadata files that embed build-time store paths
    find $out/share/gemini-cli/node_modules -name "package-lock.json" -delete
    find $out/share/gemini-cli/node_modules -name ".package-lock.json" -delete
    find $out/share/gemini-cli/node_modules -name "config.gypi" -delete
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
    license = lib.licenses.asl20;
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
    platforms = lib.platforms.all;
    mainProgram = "gemini";
  };
})
