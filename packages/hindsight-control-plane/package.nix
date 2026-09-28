{
  lib,
  flake,
  stdenv,
  fetchFromGitHub,
  nodejs,
  cacert,
  makeWrapper,
  inter,
  jetbrains-mono,
}:
let
  version = "0.10.1";

  src = fetchFromGitHub {
    owner = "vectorize-io";
    repo = "hindsight";
    tag = "v${version}";
    hash = "sha256-/qafCyuk4Vrum19AoNRtbTo+eBGP90XzNdH/LBHO4Ig=";
  };

  preparedSource = stdenv.mkDerivation {
    name = "hindsight-control-plane-${version}-prepared";
    inherit src;

    nativeBuildInputs = [
      nodejs
      cacert
    ];
    dontConfigure = true;
    # Skip fixupPhase: it would patchShebangs node_modules/.bin/* to nix store
    # bash, and fixed-output derivations may not reference store paths. The
    # build derivation runs with node on PATH, so env-based shebangs resolve.
    dontFixup = true;

    buildPhase = ''
      runHook preBuild
      export HOME=$TMPDIR
      # Node uses the system CA bundle via these env vars; the sandbox has none
      # by default, so npm's TLS handshakes fail with UNABLE_TO_GET_ISSUER_CERT.
      export SSL_CERT_FILE=${cacert}/etc/ssl/certs/ca-bundle.crt
      export NODE_EXTRA_CA_CERTS=${cacert}/etc/ssl/certs/ca-bundle.crt
      # --ignore-scripts: skip native build scripts; platform-specific binaries
      # (next/swc, esbuild, tailwind-oxide) are optional deps shipped as plain
      # tarballs and install without scripts.
      npm ci --ignore-scripts
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p $out
      cp -r . $out/
      runHook postInstall
    '';

    outputHashAlgo = "sha256";
    # The npm install resolves platform-specific optional deps (rollup/swc/
    # esbuild native binaries), so the fixed output differs per platform.
    # env-indirection keeps the hash overridable via overrideAttrs — a
    # plain let-binding can't be reached once the FOD is composed into the
    # build below, and finalAttrs-style rec is rejected inside mkDerivation
    # attrsets. Updaters override this per system.
    outputHash = "sha256-zXnPnz0X6jfYDh5fDDh3hHyJ9YtfkmAa2YwTPehVEW0=";
    outputHashMode = "recursive";
  };

  # Per-platform FOD hashes, applied to the preparedSource for the build
  # platform. Only systems with a recorded hash are buildable.
  preparedSourceHashes = {
    x86_64-linux = "sha256-zXnPnz0X6jfYDh5fDDh3hHyJ9YtfkmAa2YwTPehVEW0=";
  };
  preparedSourceForSystem = preparedSource.overrideAttrs (_: {
    outputHash =
      preparedSourceHashes.${stdenv.hostPlatform.system}
        or (throw "hindsight-control-plane: no preparedSource hash recorded for ${stdenv.hostPlatform.system}");
  });
in
stdenv.mkDerivation {
  pname = "hindsight-control-plane";
  inherit version;

  src = preparedSourceForSystem;

  nativeBuildInputs = [
    nodejs
    makeWrapper
  ];

  # next/font/google downloads Inter and JetBrains Mono from Google Fonts at
  # build time, which the sandbox blocks. Vendor the variable fonts from
  # nixpkgs and switch the layout to next/font/local instead.
  patches = [ ./local-fonts.patch ];

  postPatch = ''
    fontsDir='hindsight-control-plane/src/app/[locale]/fonts'
    mkdir -p "$fontsDir"
    cp ${inter}/share/fonts/truetype/InterVariable.ttf "$fontsDir/"
    # nixpkgs dropped the WOFF2 files from jetbrains-mono 2.304; the
    # variable TTF ships in both variants, so use that.
    cp '${jetbrains-mono}/share/fonts/truetype/JetBrainsMono[wght].ttf' \
      "$fontsDir/JetBrainsMono-Variable.ttf"
  '';

  env = {
    CI = "true";
    NEXT_TELEMETRY_DISABLED = "1";
  };

  preBuild = ''
    patchShebangs .
  '';

  buildPhase = ''
    runHook preBuild
    npm run build --workspace=hindsight-control-plane
    runHook postBuild
  '';

  postBuild = ''
    test -f hindsight-control-plane/standalone/server.js \
      || (echo "ERROR: standalone build did not produce server.js" && exit 1)
    sed -i '1s|^|#!/usr/bin/env node\n|' hindsight-control-plane/standalone/server.js
    patchShebangs hindsight-control-plane/standalone/server.js

    substituteInPlace hindsight-control-plane/bin/cli.js \
      --replace-fail "spawn('node'," "spawn('${lib.getExe nodejs}',"
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib/hindsight-control-plane
    cp -r hindsight-control-plane/standalone $out/lib/hindsight-control-plane/
    cp -r hindsight-control-plane/bin $out/lib/hindsight-control-plane/
    cp -r hindsight-control-plane/public $out/lib/hindsight-control-plane/ 2>/dev/null || true

    mkdir -p $out/bin
    makeWrapper ${lib.getExe nodejs} $out/bin/hindsight-control-plane \
      --add-flags "$out/lib/hindsight-control-plane/bin/cli.js"

    runHook postInstall
  '';

  passthru.category = "AI Assistants";

  meta = with lib; {
    description = "Hindsight Control Plane UI";
    homepage = "https://github.com/vectorize-io/hindsight";
    changelog = "https://github.com/vectorize-io/hindsight/releases/tag/v${version}";
    license = licenses.mit;
    sourceProvenance = with sourceTypes; [ fromSource ];
    maintainers = with flake.lib.maintainers; [ wanderer ];
    mainProgram = "hindsight-control-plane";
    # Only platforms with a recorded preparedSource hash (see above);
    # platform-specific optional npm deps make the fixed output per-system.
    platforms = builtins.attrNames preparedSourceHashes;
  };
}
