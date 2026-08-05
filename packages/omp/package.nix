{
  lib,
  stdenv,
  fetchFromGitHub,
  bun2nixLib,
  bun-bin,
  rustc,
  cargo,
  rustPlatform,
  pkg-config,
  makeWrapper,
  formatelf,
  zlib,
  libopus,
  python3,
  zig,
  cmake,
  libpulseaudio,
}:

let
  # omp requires bun >= 1.3.14: its whole image pipeline (provider-side
  # many-image downscaling, attachment/paste resizing, terminal rendering)
  # goes through `Bun.Image`, which nixpkgs' 1.3.13 does not have. Compiling
  # against 1.3.13 yields a binary that starts fine and then throws
  # "undefined is not a constructor" on every image, which the Anthropic
  # provider turns into an unrecoverable HTTP 400.
  bun = bun-bin;

  # bun2nix's hook propagates nixpkgs' bun, which lands earlier on PATH than
  # anything in nativeBuildInputs; `bun build --compile` would then embed that
  # runtime no matter what we pass here. Substitute the pinned bun so the
  # compiler, the embedded runtime and engines.bun all agree.
  bunHook = bun2nixLib.hook.overrideAttrs (old: {
    propagatedBuildInputs = map (p: if (p.pname or null) == "bun" then bun else p) (
      old.propagatedBuildInputs or [ ]
    );
  });
  versionData = builtins.fromJSON (builtins.readFile ./hashes.json);
  inherit (versionData) version hash cargoHash;
  platformsBySystem = {
    aarch64-darwin = {
      bunTarget = "bun-darwin-arm64";
      nativeLib = "libpi_natives.dylib";
      nodeTag = "darwin-arm64";
    };
    aarch64-linux = {
      bunTarget = "bun-linux-arm64";
      nativeLib = "libpi_natives.so";
      nodeTag = "linux-arm64";
    };
    x86_64-linux = {
      bunTarget = "bun-linux-x64-modern";
      nativeLib = "libpi_natives.so";
      nodeTag = "linux-x64";
    };
  };
  platform =
    platformsBySystem.${stdenv.hostPlatform.system}
      or (throw "Unsupported platform for omp: ${stdenv.hostPlatform.system}");
  rustTarget = stdenv.hostPlatform.rust.rustcTarget;

  src = fetchFromGitHub {
    owner = "can1357";
    repo = "oh-my-pi";
    tag = "v${version}";
    inherit hash;
  };
in
stdenv.mkDerivation {
  pname = "omp";
  inherit version src;

  cargoDeps = rustPlatform.fetchCargoVendor {
    name = "omp-${version}-cargo-vendor";
    inherit src;
    hash = cargoHash;
  };

  nativeBuildInputs = [
    bunHook
    bun
    rustc
    cargo
    rustPlatform.cargoSetupHook
    # bindgen (zlob, maudio-sys) needs libclang plus the correct clang flags
    # to find libc headers such as pthread.h.
    rustPlatform.bindgenHook
    pkg-config
    makeWrapper
    zig
    # audiopus_sys (new dependency in 17.1.3) builds bundled libopus via cmake
    cmake
  ]
  ++ lib.optionals stdenv.hostPlatform.isLinux [ formatelf ];

  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [
    stdenv.cc.cc.lib
    zlib
    # audiopus_sys links against opus (found via pkg-config)
    libopus
  ];

  # cmake is only needed by the audiopus_sys build script, not for configuring
  # this derivation itself.
  dontUseCmakeConfigure = true;

  # smallvec's `specialization` feature requires nightly Rust.
  # RUSTC_BOOTSTRAP=1 enables nightly features on stable rustc.
  env = {
    RUSTC_BOOTSTRAP = 1;
    # audiopus_sys' bundled opus ships a cmake_minimum_required older than
    # what nixpkgs' cmake 4.x still accepts.
    CMAKE_POLICY_VERSION_MINIMUM = "3.5";
  };

  bunDeps = bun2nixLib.fetchBunDeps {
    bunNix = ./bun.nix;
  };

  # Drop robomp-web workspace: its devDependencies aren't needed for the CLI.
  postUnpack = ''
        rm -rf $sourceRoot/python/robomp/web
        ROOT="$sourceRoot" ${lib.getExe python3} -c "
    import json, re, os
    root = os.environ['ROOT']

    with open(f'{root}/package.json') as f:
        pkg = json.load(f)
    ws = pkg.get('workspaces', {})
    if isinstance(ws, dict) and 'packages' in ws:
        ws['packages'] = [w for w in ws['packages'] if 'robomp/web' not in w]
    elif isinstance(ws, list):
        pkg['workspaces'] = [w for w in ws if 'robomp/web' not in w]
    with open(f'{root}/package.json', 'w') as f:
        json.dump(pkg, f, indent=2)
        f.write('\\n')

    # bun.lock uses trailing commas (JSONC), strip them for stdlib json
    with open(f'{root}/bun.lock') as f:
        text = re.sub(r',\s*([}\]])', r'\1', f.read())
    lock = json.loads(text)
    lock.get('workspaces', {}).pop('python/robomp/web', None)
    lock.get('packages', {}).pop('robomp-web', None)
    for k in list(lock.get('packages', {})):
        if k.startswith('robomp-web/'):
            del lock['packages'][k]
    with open(f'{root}/bun.lock', 'w') as f:
        json.dump(lock, f, indent=2)
        f.write('\\n')
    "
  '';

  # We handle build and install ourselves
  dontUseBunBuild = true;
  dontUseBunInstall = true;
  dontRunLifecycleScripts = true;

  # bun compile embeds JS in the binary; stripping would break it
  dontStrip = true;

  postPatch = ''
    # Strip ^ and ~ prefixes: bun resolves range specifiers via the npm
    # registry, which is unreachable in the sandbox.
    for f in package.json packages/*/package.json; do
      if [ -f "$f" ]; then
        sed -i 's/: "\^/: "/g; s/: "~/: "/g' "$f"
      fi
    done
    sed -i 's/: "\^/: "/g; s/: "~/: "/g' bun.lock

    # swarm-extension pins @oh-my-pi/pi-coding-agent to a stale major, which
    # bun can't satisfy locally and would fetch from npm. Use the workspace
    # reference instead.
    sed -i 's|"@oh-my-pi/pi-coding-agent": "[0-9][^"]*"|"@oh-my-pi/pi-coding-agent": "workspace:*"|' \
      packages/swarm-extension/package.json bun.lock

    # Placeholder client bundle avoids building the full React dashboard.
    cat > packages/stats/src/embedded-client.generated.txt <<'PLACEHOLDER'
    export const EMBEDDED_CLIENT_ARCHIVE_TAR_GZ_BASE64 = "";
    PLACEHOLDER
  '';

  buildPhase = ''
    runHook preBuild

    # Native node modules like @napi-rs/cli need libstdc++ at build time
    ${lib.optionalString stdenv.hostPlatform.isLinux ''
      export LD_LIBRARY_PATH="${lib.makeLibraryPath [ stdenv.cc.cc.lib ]}"
    ''}

    # Build the Rust native addon
    echo "Building Rust native addon..."
    cargo build --release -p pi-natives --target ${rustTarget} --target-dir target

    # Install the native addon where the JS code expects it
    mkdir -p packages/natives/native
    cp target/${rustTarget}/release/${platform.nativeLib} \
       packages/natives/native/pi_natives.${platform.nodeTag}.node

    # Generate the napi type definitions and JS loader
    napiBin="$(pwd)/node_modules/.bin/napi"
    if [ -x "$napiBin" ]; then
      "$napiBin" build \
        --manifest-path crates/pi-natives/Cargo.toml \
        --package-json-path packages/natives/package.json \
        --platform \
        --no-js \
        --dts index.d.ts \
        -o packages/natives/native \
        --release \
        || echo "napi CLI post-processing failed; using cargo output directly"
    fi

    # Generate runtime enum exports from const enums in the type definitions
    if [ -f packages/natives/scripts/gen-enums.ts ] && \
       [ -f packages/natives/native/index.d.ts ]; then
      bun packages/natives/scripts/gen-enums.ts || true
    fi

    # --generate embeds the omp:// docs index; without it the script is a no-op
    # and the binary ships no docs, breaking omp:// reads.
    echo "Generating docs index..."
    bun packages/coding-agent/scripts/generate-docs-index.ts --generate

    # Generate the embedded stats dashboard client bundle. Bun.Archive.write
    # stamps each tar header with the current time, so normalize the archive
    # afterwards to keep the compiled binary reproducible (issue #6534).
    echo "Generating embedded stats dashboard..."
    bun --cwd packages/stats scripts/generate-client-bundle.ts --generate
    bun ${./normalize-embedded-client.ts} \
      packages/stats/src/embedded-client.generated.txt

    # Generate the embedded HTML-export tool-views bundle (coding-agent prepack
    # step): export/html/index.ts text-imports ./tool-views.generated.js, which
    # bun compile cannot resolve unless it is generated first.
    echo "Generating embedded HTML-export tool-views..."
    bun --cwd packages/collab-web scripts/build-tool-views.ts

    # Since v16.4.6 mupdf is bundled into the binary and its wasm blob is
    # embedded via a generated helper (upstream gen:mupdf); --external mupdf
    # no longer works because the compiled bunfs cannot resolve it.
    echo "Embedding mupdf wasm..."
    bun packages/coding-agent/scripts/embed-mupdf-wasm.ts --generate

    # Compile the standalone binary. Since v16.4.6 the binary needs the
    # in-memory omp-legacy-pi-modules virtual module, which only the
    # Bun.build() plugin from upstream's compile-binary.ts can provide, so
    # drive that helper instead of `bun build --compile`.
    echo "Compiling standalone binary..."
    (cd packages/coding-agent && bun ${./compile-standalone.ts} "${platform.bunTarget}")

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib/omp $out/bin
    cp dist/omp $out/lib/omp/omp
    # Ship the plain addon name: native.ts probes for it on every arch.
    cp packages/natives/native/pi_natives.${platform.nodeTag}.node $out/lib/omp/

    makeWrapper $out/lib/omp/omp $out/bin/omp \
      --set PI_SKIP_VERSION_CHECK 1 \
    ${lib.optionalString stdenv.hostPlatform.isLinux "--prefix LD_LIBRARY_PATH : ${
      lib.makeLibraryPath [
        zlib
        stdenv.cc.cc.lib
        libpulseaudio
      ]
    }"}

    runHook postInstall
  '';

  # Workers and the stats dashboard only fail at runtime when their bunfs
  # entrypoints are missing; the smoke test catches that at build time.
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    HOME=$TMPDIR $out/bin/omp --smoke-test | grep -q "smoke-test: ok"
    runHook postInstallCheck
  '';

  passthru.category = "AI Coding Agents";

  meta = with lib; {
    description = "A terminal-based coding agent with multi-model support";
    homepage = "https://github.com/can1357/oh-my-pi";
    changelog = "https://github.com/can1357/oh-my-pi/releases/tag/v${version}";
    license = licenses.mit;
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
    maintainers = with maintainers; [ aldoborrero ];
    mainProgram = "omp";
    platforms = builtins.attrNames platformsBySystem;
  };
}
