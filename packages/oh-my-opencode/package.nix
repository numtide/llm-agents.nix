{
  mkUpdater,
  lib,
  flake,
  stdenv,
  bun2nixLib,
  bun,
  nodejs,
  fetchFromGitHub,
  makeWrapper,
  formatelf,
  libxcb,
}:

let
  versionData = builtins.fromJSON (builtins.readFile ./hashes.json);
  inherit (versionData)
    version
    hash
    ;

  # koffi ships prebuilt .node addons for every platform it supports;
  # keep only the one matching the host so autoPatchelf does not try to
  # resolve OpenBSD/FreeBSD/musl/foreign-arch libc symbols.
  koffiPlatform =
    if stdenv.hostPlatform.isDarwin then
      "darwin_${if stdenv.hostPlatform.isAarch64 then "arm64" else "x64"}"
    else
      "linux_${if stdenv.hostPlatform.isAarch64 then "arm64" else "x64"}";

  upstream = fetchFromGitHub {
    owner = "code-yeongyu";
    repo = "oh-my-openagent";
    tag = "v${version}";
    inherit hash;
    # packages/lsp-tools-mcp/ is a git submodule needed for the plugin's
    # built-in `lsp` MCP server.
    fetchSubmodules = true;
  };
in
stdenv.mkDerivation {
  pname = "oh-my-opencode";
  inherit version;
  src = upstream;

  # Non-empty when upstream ships a stale bun.lock; kept in sync by update.py
  patches = lib.optional (
    builtins.readFile ./fix-stale-bun-lock.patch != ""
  ) ./fix-stale-bun-lock.patch;

  # bun.lock does not record workspace lifecycle scripts. bun >= 1.4 treats
  # a workspace that has one as changed against the lockfile and re-fetches
  # the manifests of its dependencies, which fails offline. The script only
  # patches the omo-native harness, which is not part of this package.
  postPatch = ''
    substituteInPlace packages/omo-native/package.json \
      --replace-fail '"postinstall": "node bin/senpi-patch.mjs"' ""
  '';

  nativeBuildInputs = [
    bun2nixLib.hook
    bun
    nodejs
    makeWrapper
  ]
  ++ lib.optionals stdenv.hostPlatform.isLinux [ formatelf ];

  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [
    stdenv.cc.cc.lib
    # senpi-tui's linux-platform-x11.node clipboard prebuild
    libxcb
  ];

  bunDeps = bun2nixLib.fetchBunDeps {
    bunNix = ./bun.nix;
  };

  # postinstall downloads platform-specific pre-compiled binaries,
  # prepare runs the build — we handle both ourselves
  dontRunLifecycleScripts = true;
  dontUseBunBuild = true;
  dontUseBunInstall = true;

  # @opentui/core and msgpackr-extract ship glibc + musl prebuilt
  # binaries side by side; ignore the musl loader on glibc systems
  autoPatchelfIgnoreMissingDeps = [
    "libc.musl-x86_64.so.1"
    "libc.musl-aarch64.so.1"
  ];

  buildPhase = ''
    runHook preBuild

    # Build the library and CLI bundles. Since 4.9.x upstream split into a
    # monorepo, so the entry points live under packages/omo-opencode/.
    bun build packages/omo-opencode/src/index.ts --outdir dist --target bun --format esm --external zod
    bun build packages/omo-opencode/src/cli/index.ts --outdir dist/cli --target bun --format esm

    # Reproduce upstream `build:shared-skills-assets`: materialize frontend refs
    # from the (already-fetched) submodules into dist/skills, read at load time.
    bun packages/shared-skills/scripts/materialize-frontend-refs.mjs --strict
    rm -rf dist/skills
    cp -R packages/shared-skills/skills dist/skills

    # Generate the config schema (non-fatal if it fails)
    bun run build:schema || true

    # Build the bundled MCP servers. git-bash-mcp is a bun workspace; for
    # lsp-daemon (npm-managed, not a workspace) we bundle directly with bun
    # so its @oh-my-opencode/{lsp-core,mcp-stdio-core} imports resolve via
    # the root workspace node_modules and we avoid a second npm FOD.
    bun run --cwd packages/git-bash-mcp build
    bun build packages/lsp-daemon/src/cli.ts --outdir packages/lsp-daemon/dist --target node --format esm
    node packages/lsp-daemon/scripts/stamp-dist-version.mjs

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib/oh-my-opencode $out/bin

    cp -r dist node_modules package.json $out/lib/oh-my-opencode/

    # The plugin resolves its MCP servers at
    # <ancestor>/packages/{git-bash-mcp,lsp-daemon}/dist/cli.js (4.11.0
    # dropped ast-grep-mcp and replaced lsp-tools-mcp with lsp-daemon).
    mkdir -p $out/lib/oh-my-opencode/packages
    cp -r packages/{git-bash-mcp,lsp-daemon,shared-skills} $out/lib/oh-my-opencode/packages/

    # Both dist/cli.js outputs are self-contained bun bundles; their
    # node_modules only hold workspace symlinks that would dangle in $out
    # and fail noBrokenSymlinks.
    rm -rf $out/lib/oh-my-opencode/packages/git-bash-mcp/node_modules
    rm -rf $out/lib/oh-my-opencode/packages/lsp-daemon/node_modules

    # Remove broken workspace symlinks (monorepo workspace packages
    # aren't needed at runtime — the CLI bundle is self-contained)
    find $out/lib/oh-my-opencode/node_modules/@oh-my-opencode -xtype l -delete 2>/dev/null || true
    rmdir $out/lib/oh-my-opencode/node_modules/@oh-my-opencode 2>/dev/null || true

    # Drop koffi prebuilds for foreign platforms (openbsd, freebsd, musl,
    # other CPU arches) that would otherwise fail autoPatchelf.
    for dir in $out/lib/oh-my-opencode/node_modules/.bun/koffi@*/node_modules/koffi/build/koffi/*; do
      [ "$(basename "$dir")" = "${koffiPlatform}" ] || rm -rf "$dir"
    done

    makeWrapper ${bun}/bin/bun $out/bin/oh-my-opencode \
      --add-flags "run $out/lib/oh-my-opencode/dist/cli/index.js"

    runHook postInstall
  '';

  # Evaluate the installed bundle so any module-load failure (missing runtime
  # assets, broken bundle, etc.) fails the build instead of shipping silently.
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck

    ${bun}/bin/bun -e "await import('$out/lib/oh-my-opencode/dist/index.js'); console.log('ok')"

    runHook postInstallCheck
  '';

  passthru.category = "AI Coding Agents";

  passthru.updater = mkUpdater {

    kind = "script";

    tools = [ bun ];

  };

  meta = with lib; {
    description = "The Best AI Agent Harness - Multi-Model Orchestration for OpenCode";
    homepage = "https://github.com/code-yeongyu/oh-my-openagent";
    changelog = "https://github.com/code-yeongyu/oh-my-openagent/releases/tag/v${version}";
    license = flake.lib.licenses.unfree;
    sourceProvenance = with sourceTypes; [ fromSource ];
    maintainers = with flake.lib.maintainers; [ titaniumtown ];
    mainProgram = "oh-my-opencode";
    platforms = platforms.unix;
  };
}
