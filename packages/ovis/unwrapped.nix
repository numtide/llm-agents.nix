{
  lib,
  stdenv,
  flake,
  fetchFromGitHub,
  bun2nixLib,
  rustPlatform,
  bun,
  formatelf,
  mkUpdater,
  runCommand,
  patch,
}:
let
  versionData = builtins.fromJSON (builtins.readFile ./hashes.json);
  inherit (versionData) version hash cargoHash;
  src = fetchFromGitHub {
    owner = "devswha";
    repo = "ovis";
    tag = "v${version}";
    inherit hash;
  };
  # Mirrors upstream package.json; reading it from src would need IFD.
  patchedDependencies = {
    "@xterm/xterm@6.0.0" = "@xterm%2Fxterm@6.0.0.patch";
    "@legendapp/list@3.3.5" = "@legendapp%2Flist@3.3.5.patch";
  };
  # fetchBunDeps ignores overrides for packages absent from bun.nix, which would drop a patch silently.
  missingPatched = lib.filter (name: !(bunPackages ? ${name})) (lib.attrNames patchedDependencies);
  bunPackages = import ./bun.nix { fetchurl = lib.id; };
  # The server prefers this host over the Node sidecar, which stays as its fallback.
  ptySidecar = rustPlatform.buildRustPackage {
    pname = "ovis-pty-sidecar";
    inherit version src cargoHash;
    cargoRoot = "crates/pty-sidecar";
    buildAndTestSubdir = "crates/pty-sidecar";
  };
in
stdenv.mkDerivation {
  pname = "ovis-unwrapped";
  inherit version src;

  nativeBuildInputs = [
    bun2nixLib.hook
    bun
  ]
  ++ lib.optionals stdenv.hostPlatform.isLinux [ formatelf ];
  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [ stdenv.cc.cc.lib ];

  bunDeps =
    assert lib.assertMsg (
      missingPatched == [ ]
    ) "ovis: patched dependencies missing from bun.nix: ${toString missingPatched}";
    bun2nixLib.fetchBunDeps {
      bunNix = ./bun.nix;
      # The hook removes patchedDependencies; its cache must already contain the patches.
      # The helper imports patch files at evaluation time, which requires IFD for fetched sources.
      overrides = lib.mapAttrs (
        name: patchFile: pkg:
        runCommand "patched-${lib.strings.sanitizeDerivationName name}" { nativeBuildInputs = [ patch ]; }
          ''
            mkdir -p $out
            cp -r ${pkg}/. $out/
            chmod -R u+w $out
            patch -p1 -d $out < ${src}/patches/${patchFile}
          ''
      ) patchedDependencies;
    };
  dontUseBunBuild = true;
  dontUseBunInstall = true;
  dontRunLifecycleScripts = true;

  # Both programs are updated through Nix, never through the web UI.
  postPatch = ''
    substituteInPlace server/index.ts \
      --replace-fail 'herdrUpdate: new HerdrUpdater(), ' ""
  '';

  buildPhase = ''
    runHook preBuild
    bun run build
    # Upstream's own installers, so the files and their ownership banner match a manual
    # install. They write under $HOME, which bun2nix's hook points at a scratch directory.
    bun scripts/install-pi-integration.ts
    bun scripts/install-gjc-integration.ts
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/share/ovis/bin
    cp -r server shared dist node_modules package.json $out/share/ovis/
    # For pi's and GJC's extension directories; the server itself never loads them.
    install -Dm644 $HOME/.pi/agent/extensions/herdr-web-ui.js $out/share/ovis/integrations/pi/herdr-web-ui.js
    install -Dm644 $HOME/.gjc/agent/extensions/herdr-web-ui.js $out/share/ovis/integrations/gjc/herdr-web-ui.js

    # Where the server looks without OVIS_PTY_SIDECAR_BIN, which the servers it starts for
    # herdr-core's other machines never inherit; the record vouches for this binary and version.
    sidecar=${lib.getExe' ptySidecar "ovis-pty-sidecar"}
    ln -s $sidecar $out/share/ovis/bin/ovis-pty-sidecar
    printf '{"version":"%s","sha256":"%s"}\n' ${version} "$(sha256sum $sidecar | cut -d' ' -f1)" \
      > $out/share/ovis/bin/ovis-pty-sidecar.json
    ${lib.optionalString (stdenv.hostPlatform.isLinux && !stdenv.hostPlatform.isMusl) ''
      # musl variants cannot run on the glibc host and fail ELF dependency checks.
      find "$out/share/ovis/node_modules/.bun" \
        -mindepth 1 -maxdepth 1 -type d -name '*-musl@*' \
        -exec rm -rf -- {} +
      find "$out/share/ovis/node_modules" \
        -type l -name '*-musl' -delete
    ''}
    runHook postInstall
  '';

  passthru.ptySidecar = ptySidecar;
  passthru.updater = mkUpdater {
    kind = "bun-github";
    purl = "pkg:github/devswha/ovis";
    # Builds only the sidecar's vendor FOD to recover the hash.
    flakeAttr = ".#ovis.ptySidecar.cargoDeps";
    depHashKey = "cargoHash";
  };

  meta = with lib; {
    description = "Browser and phone client for herdr terminal workspaces";
    homepage = "https://github.com/devswha/ovis";
    changelog = "https://github.com/devswha/ovis/releases/tag/v${version}";
    license = licenses.mit;
    sourceProvenance = with sourceTypes; [
      fromSource
      binaryNativeCode
    ];
    maintainers = with flake.lib.maintainers; [ mulatta ];
    platforms = platforms.unix;
  };
}
