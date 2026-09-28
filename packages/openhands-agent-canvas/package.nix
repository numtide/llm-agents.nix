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
  pname = "openhands-agent-canvas";
  version = "1.24.0";

  src = fetchFromGitHub {
    owner = "OpenHands";
    repo = "OpenHands";
    tag = "v${finalAttrs.version}";
    hash = "sha256-bwt8+102/IyWdZFHcCExzxOlO+Rk6e33Pc6eytRyCoU=";
  };

  npmDepsFetcherVersion = 2;
  npmDepsHash = "sha256-BomMTl5HnJE3Pyf9xFkQy52B1VNLAe5E6QYv7WvbR8E=";

  # husky prepare hook, electron binary download
  npmFlags = [ "--ignore-scripts" ];
  env.ELECTRON_SKIP_BINARY_DOWNLOAD = "1";

  nativeBuildInputs = [ makeWrapper ];

  postPatch = ''
    # prefetch-npm-deps requires an integrity for every registry dep.
    substituteInPlace package-lock.json \
      --replace-fail '"resolved": "https://registry.npmjs.org/@babel/runtime/-/runtime-7.29.7.tgz",' \
        '"resolved": "https://registry.npmjs.org/@babel/runtime/-/runtime-7.29.7.tgz", "integrity": "sha512-Nq8OhGWiZIZGV6hLHoyAKLLcJihP/xFeBMGJoUrxTX2psI8dCifzLhZISFb+VWS3wFMRDmCGw5R+dOySCqPLhw==",'

    # vite bakes this absolute path into the bundle. Point it at $out, not the sandbox.
    substituteInPlace vite.config.ts \
      --replace-fail 'dirname(_require.resolve("@openhands/extensions/package.json"))' \
        '"${placeholder "out"}/lib/node_modules/@openhands/agent-canvas/node_modules/@openhands/extensions"'
  '';

  # The launcher fetches the Python agent-server/automation backend via uvx at
  # runtime. Pin uv to the nixpkgs interpreter so it does not download a
  # python-build-standalone that needs an FHS loader. The manylinux wheels it
  # installs dlopen libstdc++.
  postInstall = ''
    find $out/lib/node_modules -name '*.map' -delete
    wrapProgram $out/bin/agent-canvas \
      --prefix PATH : ${lib.makeBinPath [ uv ]} \
      --set-default UV_PYTHON ${python3.interpreter} \
      ${lib.optionalString stdenv.hostPlatform.isLinux "--prefix LD_LIBRARY_PATH : ${
        lib.makeLibraryPath [ stdenv.cc.cc.lib ]
      }"}
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [ versionCheckHook ];

  passthru.category = "AI Coding Agents";

  meta = {
    description = "Self-hosted web UI for running OpenHands, Claude Code, Codex and other ACP agents";
    homepage = "https://github.com/OpenHands/OpenHands";
    changelog = "https://github.com/OpenHands/OpenHands/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.mit;
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
    maintainers = with flake.lib.maintainers; [ jiezhuzzz ];
    mainProgram = "agent-canvas";
    platforms = lib.platforms.unix;
  };
})
