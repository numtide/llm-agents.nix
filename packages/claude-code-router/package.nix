{
  lib,
  stdenv,
  buildNpmPackage,
  fetchFromGitHub,
  fetchzip,
  python3,
  nodejs,
}:

buildNpmPackage (finalAttrs: {
  pname = "claude-code-router";
  version = "3.1.6";

  # The GitHub repo carries package-lock.json (needed for npmDepsHash) but
  # not the built dist/ tree; the npm registry tarball is the other way
  # round. We install runtime dependencies from the former and drop the
  # prebuilt bundle from the latter on top, avoiding the fragile
  # Electron/React devDependency set required to rebuild dist/ from source.
  src = fetchFromGitHub {
    owner = "musistudio";
    repo = "claude-code-router";
    tag = "v${finalAttrs.version}";
    hash = "sha256-HEeJcKgghTdJQ1PY2Ctgk/R2ddQ1gq/O4WxQWyjsnjM=";
  };

  dist = fetchzip {
    url = "https://registry.npmjs.org/@musistudio/claude-code-router/-/claude-code-router-${finalAttrs.version}.tgz";
    hash = "sha256-W1LlmXj9vxgE/OpwqHR9a/BVkweUlMbzRVmzPwaoP2I=";
  };

  npmDepsHash = "sha256-CSyVWBXb8kX/aQDpp7HhtvKZp0orJ2SDNtbnT6wYUqI=";

  # Upstream is an npm workspace monorepo; the published CLI lives in
  # packages/cli.
  npmWorkspace = "packages/cli";

  dontNpmBuild = true;

  # Only production dependencies are needed at runtime; devDependencies
  # pull in Electron/React with unresolved peer deps upstream.
  npmFlags = [
    "--omit=dev"
    "--legacy-peer-deps"
  ];
  # The CLI workspace's prepack script tries to rebuild dist/ with the
  # devDependency toolchain we deliberately omit; the prebuilt bundle from
  # the npm registry is copied in preInstall instead.
  npmPackFlags = [ "--ignore-scripts" ];
  makeCacheWritable = true;

  nativeBuildInputs = [
    python3 # better-sqlite3 node-gyp rebuild
  ];

  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [
    stdenv.cc.cc.lib # better-sqlite3 native addon
  ];

  env = {
    ELECTRON_SKIP_BINARY_DOWNLOAD = "1";
    # better-sqlite3 ships prebuild-install prebuilds; force a source build
    # so the resulting .node targets nixpkgs' node ABI and libc.
    npm_config_build_from_source = "true";
  };

  # npm pack (used by npmInstallHook) only ships paths listed in
  # package.json#files, so the prebuilt bundle has to be in place first.
  preInstall = ''
    cp -r ${finalAttrs.dist}/dist packages/cli/dist
    chmod -R u+w packages/cli/dist
  '';

  postInstall = ''
    # Drop node-gyp intermediate objects that leak /build/ references.
    rm -rf $out/lib/node_modules/claude-code-router-monorepo/node_modules/better-sqlite3/build/Release/obj.target
    # The workspace symlinks point at packages/ sources that npm pack does
    # not ship; the published dist/ bundle inlines those workspace packages.
    rm -f $out/lib/node_modules/claude-code-router-monorepo/node_modules/.bin/ccr \
      $out/lib/node_modules/claude-code-router-monorepo/node_modules/@musistudio/claude-code-router \
      $out/lib/node_modules/claude-code-router-monorepo/node_modules/@claude-code-router/{core,electron,ui}
  '';

  # Upstream's 3.x CLI has no --version/-v flag and every subcommand aborts
  # early without a configured provider, so we treat that guarded exit as a
  # smoke test: reaching it means node, better-sqlite3 and the bundled
  # dist/ all loaded correctly.
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    # ccr exits non-zero on the guard message; capture instead of piping
    # so stdenv's pipefail does not fail the phase before grep runs.
    output=$(HOME=$TMPDIR $out/bin/ccr help 2>&1 || true)
    grep -q "Configure at least one provider" <<<"$output"
    runHook postInstallCheck
  '';

  passthru = {
    inherit (finalAttrs) dist;
    category = "Claude Code Ecosystem";
  };

  meta = with lib; {
    description = "Use Claude Code without an Anthropics account and route it to another LLM provider";
    homepage = "https://github.com/musistudio/claude-code-router";
    changelog = "https://github.com/musistudio/claude-code-router/releases/tag/v${finalAttrs.version}";
    license = licenses.mit;
    sourceProvenance = with sourceTypes; [
      fromSource
      binaryBytecode # bundled dist/ from npm registry
    ];
    maintainers = with maintainers; [ ];
    mainProgram = "ccr";
    inherit (nodejs.meta) platforms;
  };
})
