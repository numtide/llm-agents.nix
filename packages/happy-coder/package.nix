{
  mkUpdater,
  lib,
  stdenv,
  fetchFromGitHub,
  fetchPnpmDeps,
  nodejs,
  pnpm_10,
  pnpmConfigHook,
  makeWrapper,
  versionCheckHook,
  versionCheckHomeHook,
  ripgrep,
  difftastic,
}:

let
  pin = lib.importJSON ./hashes.json;

  # The CLI lives in slopus/happy, a pnpm-workspaces monorepo that does
  # not tag the CLI (the only tags refer to the mobile app). We track the
  # `happy` npm version and pin the monorepo commit that bumped
  # packages/happy-cli/package.json to it, then build from source.
  pnpmWorkspaces = [
    "happy"
    "@slopus/happy-wire"
  ];
in
stdenv.mkDerivation (finalAttrs: {
  pname = "happy-coder";
  inherit (pin) version;

  src = fetchFromGitHub {
    owner = "slopus";
    repo = "happy";
    rev = pin.srcRev;
    hash = pin.srcHash;
  };

  pnpmDeps = fetchPnpmDeps {
    inherit (finalAttrs) pname version src;
    inherit pnpmWorkspaces;
    pnpm = pnpm_10;
    hash = pin.pnpmDepsHash;
    fetcherVersion = 3;
  };

  inherit pnpmWorkspaces;

  nativeBuildInputs = [
    nodejs
    pnpm_10
    pnpmConfigHook
    makeWrapper
  ];

  buildPhase = ''
    runHook preBuild

    pnpm --filter @slopus/happy-wire build
    pnpm --filter happy build

    runHook postBuild
  '';

  # Upstream's postinstall (scripts/unpack-tools.cjs) extracts a 100 MB
  # multi-platform tarball collection (ripgrep / difftastic / a ripgrep
  # NAPI addon) into tools/unpacked/. The Mach-O / glibc binaries don't
  # work in the Nix sandbox anyway, so:
  #   - skip the script (pnpmConfigHook already passes --ignore-scripts)
  #   - drop the archives to slim down the closure
  #   - symlink nixpkgs' ripgrep + difftastic so the hardcoded
  #     `tools/unpacked/{rg,difft}` lookups succeed
  #   - leave ripgrep.node missing — ripgrep_launcher.cjs falls back to
  #     the rg binary (and to PATH) when require() on the addon fails.
  #
  # The monorepo uses node-linker=hoisted, so the CLI shares the root
  # node_modules. Ship the pruned root tree alongside the built workspace
  # packages, and let bin/ live where it expects ../dist.
  installPhase = ''
    runHook preInstall

    # pnpm 10's non-legacy deploy uses the shared lockfile (offline) but
    # requires inject-workspace-packages so the @slopus/happy-wire link
    # is materialised as a real directory rather than a workspace symlink.
    pnpm config set inject-workspace-packages true
    pnpm --filter happy --prod --ignore-scripts deploy $out/lib/happy

    rm -rf $out/lib/happy/tools/archives $out/lib/happy/tools/unpacked
    mkdir -p $out/lib/happy/tools/unpacked
    ln -s ${lib.getExe ripgrep} $out/lib/happy/tools/unpacked/rg
    ln -s ${lib.getExe difftastic} $out/lib/happy/tools/unpacked/difft

    mkdir -p $out/bin
    # happy ignores a PATH `claude` that resolves to an extensionless script
    # (every Nix-wrapped claude-code), but trusts HAPPY_CLAUDE_PATH as given.
    for bin in happy happy-mcp; do
      makeWrapper ${nodejs}/bin/node $out/bin/$bin \
        --add-flags --no-warnings \
        --add-flags --no-deprecation \
        --add-flags $out/lib/happy/bin/$bin.mjs \
        --run 'export HAPPY_CLAUDE_PATH="''${HAPPY_CLAUDE_PATH:-$(command -v claude || true)}"' \
        --prefix PATH : ${
          lib.makeBinPath [
            nodejs
            ripgrep
            difftastic
          ]
        }
    done

    runHook postInstall
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [
    versionCheckHook
    versionCheckHomeHook
  ];

  passthru.category = "Utilities";

  passthru.updater = mkUpdater { kind = "script"; };

  meta = {
    description = "Mobile and Web client for Codex and Claude Code, with realtime voice and encryption";
    homepage = "https://github.com/slopus/happy";
    changelog = "https://github.com/slopus/happy/commits/main/packages/happy-cli";
    downloadPage = "https://www.npmjs.com/package/happy";
    license = lib.licenses.mit;
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
    maintainers = with lib.maintainers; [ ];
    mainProgram = "happy";
    platforms = lib.platforms.all;
  };
})
