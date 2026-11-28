{
  mkUpdater,
  lib,
  flake,
  stdenvNoCC,
  fetchurl,
  makeWrapper,
  bun,
  bun2nixLib,
  versionCheckHook,
  versionCheckHomeHook,
}:

let
  versionData = lib.importJSON ./hashes.json;
  inherit (versionData) version hash;
in
stdenvNoCC.mkDerivation {
  pname = "opencodex";
  inherit version;

  # The npm tarball ships the prebuilt gui/dist but no lockfile. bun.lock is
  # vendored from the matching git tag by update.py.
  src = fetchurl {
    url = "https://registry.npmjs.org/@bitkyc08/opencodex/-/opencodex-${version}.tgz";
    inherit hash;
  };
  sourceRoot = "package";

  postPatch = ''
    cp ${./bun.lock} bun.lock
  '';

  nativeBuildInputs = [
    bun2nixLib.hook
    makeWrapper
  ];

  bunDeps = bun2nixLib.fetchBunDeps {
    bunNix = ./bun.nix;
  };
  bunInstallFlags = [
    "--linker=isolated"
    "--backend=symlink"
    "--production"
  ];

  dontUseBunBuild = true;
  dontUseBunInstall = true;
  # The npm `bun` dep's postinstall downloads a bun binary.
  dontRunLifecycleScripts = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib/opencodex $out/bin
    # Nix provides bun. Drop the npm copy of the runtime.
    rm -rf node_modules/.bun/bun@* node_modules/.bun/@oven+* node_modules/.bin
    find node_modules -xtype l -delete
    cp -r bin gui src package.json node_modules $out/lib/opencodex/

    makeWrapper ${lib.getExe bun} $out/bin/ocx \
      --add-flags "$out/lib/opencodex/src/cli/index.ts"
    ln -s ocx $out/bin/opencodex

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
    description = "Universal provider proxy for OpenAI Codex, Claude Code, Claude Desktop & Grok Build";
    homepage = "https://github.com/lidge-jun/opencodex";
    changelog = "https://github.com/lidge-jun/opencodex/releases/tag/v${version}";
    license = lib.licenses.mit;
    mainProgram = "ocx";
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
    inherit (bun.meta) platforms;
    maintainers = with flake.lib.maintainers; [ bet4it ];
  };
}
