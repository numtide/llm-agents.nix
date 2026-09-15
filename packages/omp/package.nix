{
  lib,
  stdenv,
  fetchFromGitHub,
  bun2nixLib,
  bun,
  rustc,
  cargo,
  rustPlatform,
  pkg-config,
  cmake,
  ninja,
  makeWrapper,
  rcodesign,
  formatelf,
  zlib,
  python3,
  zig,
  libpulseaudio,
  pipewire,
}:

let
  versionData = builtins.fromJSON (builtins.readFile ./hashes.json);
  inherit (versionData) version hash cargoHash;
  platformsBySystem = {
    aarch64-darwin = {
      nativeLib = "libpi_natives.dylib";
      nodeTag = "darwin-arm64";
    };
    aarch64-linux = {
      nativeLib = "libpi_natives.so";
      nodeTag = "linux-arm64";
    };
    x86_64-linux = {
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
    bun2nixLib.hook
    bun
    rustc
    cargo
    rustPlatform.cargoSetupHook
    # bindgen (zlob, maudio-sys) needs libclang and clang flags for libc headers
    rustPlatform.bindgenHook
    pkg-config
    # opusic-sys compiles its bundled libopus with cmake -G Ninja
    cmake
    ninja
    makeWrapper
    zig
  ]
  ++ lib.optionals stdenv.hostPlatform.isLinux [ formatelf ]
  ++ lib.optionals stdenv.hostPlatform.isDarwin [ rcodesign ];

  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [
    stdenv.cc.cc.lib
    zlib
    # pi-natives' wayland-pipewire feature links system libpipewire (pkg-config)
    pipewire
  ];

  env = {
    # smallvec's `specialization` feature needs nightly features on stable rustc
    RUSTC_BOOTSTRAP = 1;
    # upstream's release profile is fat LTO with one codegen unit; that final
    # link runs silently for 10+ minutes and CI builders kill it. Use the
    # settings of upstream's own `ci` profile instead.
    CARGO_PROFILE_RELEASE_LTO = "thin";
    CARGO_PROFILE_RELEASE_CODEGEN_UNITS = 16;
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

  dontUseCmakeConfigure = true;
  dontUseBunBuild = true;
  dontUseBunInstall = true;
  dontRunLifecycleScripts = true;

  # bun compile embeds JS in the binary. Stripping would break it.
  dontStrip = true;

  postPatch = ''
    # Upstream bug: everything else imports the pi-utils re-export; bare
    # chalk is only reachable through a devDependency.
    substituteInPlace packages/coding-agent/src/cli/collab-cli.ts \
      --replace-fail 'from "chalk"' 'from "@oh-my-pi/pi-utils/chalk"'

    # Strip ^ and ~ prefixes: bun resolves range specifiers via the npm
    # registry, which is unreachable in the sandbox.
    for f in package.json packages/*/package.json; do
      if [ -f "$f" ]; then
        sed -i 's/: "\^/: "/g; s/: "~/: "/g' "$f"
      fi
    done
    sed -i 's/: "\^/: "/g; s/: "~/: "/g' bun.lock


    # Placeholder client bundle avoids building the full React dashboard.
    cat > packages/stats/src/embedded-client.generated.txt <<'PLACEHOLDER'
    export const EMBEDDED_CLIENT_ARCHIVE_TAR_GZ_BASE64 = "";
    PLACEHOLDER
  '';

  buildPhase = ''
    runHook preBuild

    ${lib.optionalString stdenv.hostPlatform.isLinux ''
      export LD_LIBRARY_PATH="${lib.makeLibraryPath [ stdenv.cc.cc.lib ]}"
    ''}

    echo "Building Rust native addon..."
    cargo build --release -p pi-natives \
      ${lib.optionalString stdenv.hostPlatform.isLinux "--features wayland-pipewire"} \
      --target ${rustTarget} --target-dir target

    mkdir -p packages/natives/native
    cp target/${rustTarget}/release/${platform.nativeLib} \
       packages/natives/native/pi_natives.${platform.nodeTag}.node

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

    if [ -f packages/natives/scripts/gen-enums.ts ] && \
       [ -f packages/natives/native/index.d.ts ]; then
      bun packages/natives/scripts/gen-enums.ts || true
    fi

    # --generate embeds the omp:// docs index. Without it the script is a no-op
    # and the binary ships no docs, breaking omp:// reads.
    echo "Generating docs index..."
    bun packages/coding-agent/scripts/generate-docs-index.ts --generate

    # Bun.Archive.write stamps tar headers with the current time. Normalize
    # afterwards for reproducibility (issue #6534).
    echo "Generating embedded stats dashboard..."
    bun --cwd packages/stats scripts/generate-client-bundle.ts --generate
    bun ${./normalize-embedded-client.ts} \
      packages/stats/src/embedded-client.generated.txt

    # export/html/index.ts text-imports ./tool-views.generated.js, which must
    # exist before bun compile.
    echo "Generating embedded HTML-export tool-views..."
    bun --cwd packages/collab-web scripts/build-tool-views.ts

    # compile-standalone.ts drives upstream's compile-binary.ts helper because
    # `bun build --compile` cannot load the required virtual-module plugin.
    echo "Compiling standalone binary..."
    (cd packages/coding-agent && bun ${./compile-standalone.ts})

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
        pipewire
      ]
    }"}

    runHook postInstall
  '';

  # Re-sign after fixup: install_name_tool and Bun can leave invalid signatures
  postFixup = lib.optionalString stdenv.hostPlatform.isDarwin ''
    ${lib.getExe rcodesign} sign --code-signature-flags linker-signed $out/lib/omp/omp
  '';

  # Workers and the stats dashboard only fail at runtime when their bunfs
  # entrypoints are missing. The smoke test catches that at build time.
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    HOME=$TMPDIR $out/bin/omp --smoke-test | grep -q "smoke-test: ok"
    BUN_BE_BUN=1 $out/lib/omp/omp -e \
      'if (Bun.version !== "${bun.version}" || typeof Bun.Image !== "function") process.exit(1)'
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
