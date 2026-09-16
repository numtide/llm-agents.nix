{
  lib,
  stdenvNoCC,
  platformSource,
  mkUpdater,
  unzip,
  codesignCheckHook,
}:

# Unmodified upstream bun to be used as `bun build --compile --target` runtime.
# A patchelf'd bun >= 1.3.14 embeds its runtime twice and the result segfaults
# (see 7ef80847), so packages that need a newer runtime than nixpkgs' bun seed
# the cross-compile cache with this instead.
let
  triples = {
    x86_64-linux = "linux-x64-baseline";
    aarch64-linux = "linux-aarch64";
    aarch64-darwin = "darwin-aarch64";
  };
  source = platformSource {
    hashesFile = ./hashes.json;
    platforms = triples;
    urlTemplate = "https://github.com/oven-sh/bun/releases/download/bun-v{version}/bun-{platform}.zip";
  };
  target = "bun-${triples.${stdenvNoCC.hostPlatform.system}}-v${source.version}";
in
stdenvNoCC.mkDerivation {
  pname = "bun-bin";
  inherit (source) version src;

  nativeBuildInputs = [ unzip ];

  dontFixup = true;

  doInstallCheck = true;
  nativeInstallCheckInputs = [ codesignCheckHook ];
  codesignTeamId = "7FRXF46ZSN";
  codesignSources = source.darwinSrcs;

  installPhase = ''
    runHook preInstall
    install -Dm755 bun $out/share/bun-bin/${target}
    runHook postInstall
  '';

  passthru = {
    hideFromDocs = true;
    # Copy share/bun-bin/* into $BUN_INSTALL_CACHE_DIR and pass --target.
    inherit target;
    updater = mkUpdater (
      source.updater
      // {
        versionSource = {
          type = "text";
          url = "https://api.github.com/repos/oven-sh/bun/releases/latest";
          regex = ''"tag_name": *"bun-v([^"]+)"'';
        };
      }
    );
  };

  meta = {
    description = "Upstream bun binary for use as a bun --compile runtime";
    homepage = "https://bun.sh";
    license = lib.licenses.mit;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    inherit (source) platforms;
  };
}
