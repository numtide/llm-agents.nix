{
  lib,
  stdenv,
  fetchFromGitHub,
  mkUpdater,
  bun2nixLib,
  bun,
  makeWrapper,
  installAgentSkills,
  sqlite,
  formatelf,
  flake,

  # GPU support
  config,
  cudaSupport ? config.cudaSupport or false,
  cudaPackages ? { },
  cudaPackages_12,
  vulkanSupport ? stdenv.hostPlatform.isLinux,
  vulkan-loader,
  autoAddDriverRunpath,
}:
let
  # CUDA only supported on x86_64-linux
  effectiveCudaSupport = cudaSupport && stdenv.hostPlatform.isLinux && stdenv.hostPlatform.isx86_64;
  hasCuda13Runtime = effectiveCudaSupport && lib.versionAtLeast cudaPackages.cuda_cudart.version "13";
  # node-llama-cpp bundles both CUDA 13 and CUDA 12 fallback binaries. Keep
  # both loadable when the consumer's default cudaPackages moves to CUDA 13.
  cudaRuntimeLibraries = lib.optionals effectiveCudaSupport (
    [
      cudaPackages.cuda_cudart
      cudaPackages.libcublas
    ]
    ++ lib.optionals hasCuda13Runtime [
      cudaPackages_12.cuda_cudart
      cudaPackages_12.libcublas
    ]
  );
  # Vulkan supported on all Linux
  effectiveVulkanSupport = vulkanSupport && stdenv.hostPlatform.isLinux;
  vulkanRuntimeLibraries = lib.optionals effectiveVulkanSupport [ vulkan-loader ];

  versionData = builtins.fromJSON (builtins.readFile ./hashes.json);
  inherit (versionData) version hash;
in
stdenv.mkDerivation {
  pname = "qmd";
  inherit version;

  src = fetchFromGitHub {
    owner = "tobi";
    repo = "qmd";
    tag = "v${version}";
    inherit hash;
  };

  nativeBuildInputs = [
    bun2nixLib.hook
    makeWrapper
    installAgentSkills
  ]
  ++ lib.optionals stdenv.hostPlatform.isLinux [ formatelf ]
  ++ lib.optionals effectiveCudaSupport [ autoAddDriverRunpath ];

  buildInputs = [
    sqlite
  ]
  ++ lib.optionals stdenv.hostPlatform.isLinux [
    stdenv.cc.cc.lib # For libgcc_s.so.1 and libstdc++.so.6
  ]
  ++ cudaRuntimeLibraries
  ++ vulkanRuntimeLibraries;

  bunDeps = bun2nixLib.fetchBunDeps {
    bunNix = ./bun.nix;
  };

  # Ignore missing optional dependencies based on enabled GPU backends
  autoPatchelfIgnoreMissingDeps = [
    # musl (we use glibc)
    "libc.musl-x86_64.so.1"
    "libc.musl-aarch64.so.1"
  ]
  # CUDA 12 configurations use the bundled fallback instead of CUDA 13 binaries.
  ++ lib.optionals (!hasCuda13Runtime) [
    "libcudart.so.13"
    "libcublas.so.13"
  ]
  ++ [
    # libcuda.so.1 comes from the NVIDIA driver (autoAddDriverRunpath).
    "libcuda.so.1"
  ]
  # CUDA-enabled configurations always provide the CUDA 12 fallback libraries.
  ++ lib.optionals (!effectiveCudaSupport) [
    "libcudart.so.12"
    "libcublas.so.12"
  ]
  ++ lib.optionals (!effectiveVulkanSupport) [
    "libvulkan.so.1"
  ];

  # we run src with bun; the prepare script only builds dist for node
  postPatch = ''
    substituteInPlace package.json \
      --replace-fail '"prepare": "node scripts/install-hooks.mjs && node scripts/build.mjs",' ""
  '';

  # avoid bun's shared /private/tmp/bun-node-* shim on darwin
  preBunLifecycleScriptsPhase = ''
    mkdir -p $TMPDIR/node-shim
    ln -s ${lib.getExe bun} $TMPDIR/node-shim/node
    export PATH=$TMPDIR/node-shim:$PATH
  '';

  # No build step needed - we'll run directly with bun
  dontUseBunBuild = true;
  dontUseBunInstall = true;

  installPhase =
    let
      # Build LD_LIBRARY_PATH with all required libraries
      ldLibraryPath =
        lib.makeLibraryPath ([ sqlite.out ] ++ cudaRuntimeLibraries ++ vulkanRuntimeLibraries)
        # Add NixOS driver path for libcuda.so.1 (loaded via dlopen at runtime)
        + lib.optionalString effectiveCudaSupport ":/run/opengl-driver/lib";
    in
    ''
      runHook preInstall

      mkdir -p $out/lib/qmd $out/bin

      cp -r node_modules src package.json $out/lib/qmd/

      # Patch detectGlibc.js to always return true on Linux
      # node-llama-cpp checks FHS paths (/lib, /usr/lib) for glibc which don't exist on NixOS
      # Without this patch, it falls back to building llama.cpp which fails in read-only store
      patch -p1 -d $out/lib/qmd < ${../../patches/node-llama-cpp-detectGlibc.patch}

      # Redirect writable paths (localBuilds, llama.cpp clone, toolchains, xpack,
      # build metadata) from the read-only Nix store to ~/.cache/node-llama-cpp.
      # When the prebuilt CUDA binary fails its compatibility test, node-llama-cpp
      # falls back to building llama.cpp from source, which requires cloning the
      # repo and writing build artifacts. On NixOS these paths resolve to
      # /nix/store/... which is read-only, causing EROFS errors.
      # Read-only assets (prebuilt bins, grammars, git bundle, release JSON) are
      # kept pointing to the Nix store.
      patch -p1 -d $out/lib/qmd < ${./node-llama-cpp-nix-compat.patch}

      makeWrapper ${bun}/bin/bun $out/bin/qmd \
        --add-flags "$out/lib/qmd/src/cli/qmd.ts" \
        --set DYLD_LIBRARY_PATH "${sqlite.out}/lib" \
        --set LD_LIBRARY_PATH "${ldLibraryPath}"

      runHook postInstall
    '';

  # Only export the user-facing skill, not the upstream release workflow.
  dontInstallAgentSkills = true;
  postInstall = ''
    installSkill skills/qmd
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    test -f $out/share/skills/qmd/qmd/SKILL.md
    test -f $out/share/skills/qmd/qmd/references/mcp-setup.md
    test ! -e $out/share/skills/qmd/release
    # Test --help works
    HOME=$(mktemp -d) $out/bin/qmd --help | grep -q "Usage:"
    # Test actual database initialization (requires sqlite extension loading)
    HOME=$(mktemp -d) $out/bin/qmd status
    runHook postInstallCheck
  '';

  passthru.category = "Memory & Code Intelligence";
  passthru.updater = mkUpdater {
    kind = "bun-github";
    purl = "pkg:github/tobi/qmd";
  };

  meta = with lib; {
    description = "mini cli search engine for your docs, knowledge bases, meeting notes, whatever. Tracking current sota approaches while being all local";
    homepage = "https://github.com/tobi/qmd";
    changelog = "https://github.com/tobi/qmd/releases/tag/v${version}";
    license = licenses.mit;
    sourceProvenance = with lib.sourceTypes; [
      fromSource
      binaryNativeCode
    ];
    maintainers = with flake.lib.maintainers; [ mulatta ];
    platforms = lib.platforms.unix;
    mainProgram = "qmd";
  };
}
