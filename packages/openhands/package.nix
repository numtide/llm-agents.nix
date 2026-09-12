{
  lib,
  stdenv,
  flake,
  buildNpmPackage,
  fetchFromGitHub,
  makeWrapper,
  python3,
  uv,
  versionCheckHook,
}:

buildNpmPackage (finalAttrs: {
  npmDepsFetcherVersion = 2;
  pname = "openhands";
  version = "1.17.0";

  src = fetchFromGitHub {
    owner = "OpenHands";
    repo = "OpenHands";
    tag = "v${finalAttrs.version}";
    hash = "sha256-IipdKgsEwo0ckcYH685SP4rPQkqb/YcCYjN+ppQHoZA=";
  };

  npmDepsHash = "sha256-yWvXQdYgeWpMsRMmG4pDpvEyHIEqClsnl9USQmOyWDU=";

  # husky's prepare hook and electron's binary download are dev-only.
  npmFlags = [ "--ignore-scripts" ];
  env.ELECTRON_SKIP_BINARY_DOWNLOAD = "1";

  nativeBuildInputs = [ makeWrapper ];

  postPatch = ''
    # Upstream's lockfile carries no integrity for @babel/runtime, which
    # prefetch-npm-deps rejects ("non-git dependencies should have associated
    # integrity").
    substituteInPlace package-lock.json \
      --replace-fail '"resolved": "https://registry.npmjs.org/@babel/runtime/-/runtime-7.29.7.tgz",' \
        '"resolved": "https://registry.npmjs.org/@babel/runtime/-/runtime-7.29.7.tgz", "integrity": "sha512-Nq8OhGWiZIZGV6hLHoyAKLLcJihP/xFeBMGJoUrxTX2psI8dCifzLhZISFb+VWS3wFMRDmCGw5R+dOySCqPLhw==",'

    # vite bakes the absolute path of @openhands/extensions/skills into the
    # bundle so agent-server can resolve bundled skill resources; point it at
    # the installed location instead of the build sandbox.
    substituteInPlace vite.config.ts \
      --replace-fail 'dirname(_require.resolve("@openhands/extensions/package.json"))' \
        '"${placeholder "out"}/lib/node_modules/@openhands/agent-canvas/node_modules/@openhands/extensions"'
  '';

  # The launcher runs the Python agent-server and automation backend from
  # PyPI via uvx. uv prefers its own managed interpreters (possibly a
  # free-threaded build without wheels for the SDK's native deps) and, on
  # NixOS, downloads a python-build-standalone that needs an FHS loader, so
  # pin it to the nixpkgs interpreter unless the user overrides. The
  # manylinux wheels it installs (tokenizers, ...) dlopen libstdc++.
  postInstall = ''
    wrapProgram $out/bin/agent-canvas \
      --prefix PATH : ${lib.makeBinPath [ uv ]} \
      --set-default UV_PYTHON ${python3.interpreter} \
      ${lib.optionalString stdenv.hostPlatform.isLinux "--prefix LD_LIBRARY_PATH : ${
        lib.makeLibraryPath [ stdenv.cc.cc.lib ]
      }"}
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [ versionCheckHook ];
  versionCheckProgramArg = "--version";

  passthru.category = "AI Coding Agents";

  meta = {
    description = "OpenHands Agent Canvas, a self-hosted control center for running OpenHands, Claude Code, Codex, and other ACP coding agents";
    homepage = "https://github.com/OpenHands/OpenHands";
    changelog = "https://github.com/OpenHands/OpenHands/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.mit;
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
    maintainers = with flake.lib.maintainers; [ jiezhuzzz ];
    mainProgram = "agent-canvas";
    platforms = lib.platforms.unix;
  };
})
