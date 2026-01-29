{
  lib,
  stdenv,
  buildNpmPackage,
  fetchFromGitHub,
  bun,
  makeWrapper,
  sqlite,
  fetchNpmDepsWithPackuments,
  npmConfigHook,
  jq,
  autoPatchelfHook,
  flake,

  # GPU support
  config,
  cudaSupport ? config.cudaSupport or false,
  cudaPackages ? { },
  vulkanSupport ? stdenv.isLinux,
  vulkan-loader,
  autoAddDriverRunpath,
}:
let
  # CUDA only supported on x86_64-linux
  effectiveCudaSupport = cudaSupport && stdenv.isLinux && stdenv.hostPlatform.isx86_64;
  # Vulkan supported on all Linux
  effectiveVulkanSupport = vulkanSupport && stdenv.isLinux;

  versionData = builtins.fromJSON (builtins.readFile ./hashes.json);
  inherit (versionData) rev srcHash npmDepsHash;

  version = "1.0.0-unstable";

  src = fetchFromGitHub {
    owner = "tobi";
    repo = "qmd";
    inherit rev;
    hash = srcHash;
  };

  # Shared patch: add package-lock.json and remove win32 optional dependency
  postPatch = ''
    cp ${./package-lock.json} package-lock.json
    # Remove win32 optional dependency from package.json to match our package-lock.json
    ${jq}/bin/jq 'del(.optionalDependencies."sqlite-vec-win32-x64")' package.json > package.json.tmp
    mv package.json.tmp package.json
  '';
in
buildNpmPackage {
  inherit
    npmConfigHook
    version
    src
    postPatch
    ;
  pname = "qmd";

  npmDeps = fetchNpmDepsWithPackuments {
    inherit src postPatch;
    name = "qmd-${version}-npm-deps";
    hash = npmDepsHash;
    fetcherVersion = 2;
  };
  makeCacheWritable = true;

  nativeBuildInputs = [
    makeWrapper
  ]
  ++ lib.optionals stdenv.isLinux [ autoPatchelfHook ]
  ++ lib.optionals effectiveCudaSupport [ autoAddDriverRunpath ];

  buildInputs = [
    sqlite
  ]
  ++ lib.optionals stdenv.isLinux [
    stdenv.cc.cc.lib # For libgcc_s.so.1 and libstdc++.so.6
  ]
  ++ lib.optionals effectiveCudaSupport [
    cudaPackages.cuda_cudart
    cudaPackages.libcublas
  ]
  ++ lib.optionals effectiveVulkanSupport [
    vulkan-loader
  ];

  # Ignore missing optional dependencies based on enabled GPU backends
  autoPatchelfIgnoreMissingDeps =
    # Always ignore musl (we use glibc)
    [
      "libc.musl-x86_64.so.1"
      "libc.musl-aarch64.so.1"
    ]
    # Ignore CUDA libs - they're loaded at runtime via LD_LIBRARY_PATH
    # libcuda.so.1 comes from nvidia driver (autoAddDriverRunpath)
    # Prebuilt binaries want CUDA 13 but we provide CUDA 12 (ABI compatible)
    ++ lib.optionals (!effectiveCudaSupport) [
      "libcudart.so.12"
      "libcudart.so.13"
      "libcublas.so.12"
      "libcublas.so.13"
      "libcuda.so.1"
    ]
    ++ lib.optionals effectiveCudaSupport [
      # Always ignore these - loaded at runtime
      "libcudart.so.13"
      "libcublas.so.13"
      "libcuda.so.1" # from nvidia driver
    ]
    # Ignore Vulkan libs if Vulkan support is disabled
    ++ lib.optionals (!effectiveVulkanSupport) [
      "libvulkan.so.1"
    ];

  # Skip any build scripts since this is a TypeScript project run with bun
  npmFlags = [ "--ignore-scripts" ];

  # No build step needed - we'll run directly with bun
  dontNpmBuild = true;

  installPhase =
    let
      # Build LD_LIBRARY_PATH with all required libraries
      ldLibraryPath =
        lib.makeLibraryPath (
          [ sqlite.out ]
          ++ lib.optionals effectiveCudaSupport [
            cudaPackages.cuda_cudart
            cudaPackages.libcublas
          ]
          ++ lib.optionals effectiveVulkanSupport [
            vulkan-loader
          ]
        )
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
      patch -p1 -d $out/lib/qmd < ${./node-llama-cpp-detectGlibc.patch}

      makeWrapper ${bun}/bin/bun $out/bin/qmd \
        --add-flags "$out/lib/qmd/src/qmd.ts" \
        --set DYLD_LIBRARY_PATH "${sqlite.out}/lib" \
        --set LD_LIBRARY_PATH "${ldLibraryPath}"

      runHook postInstall
    '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    # Test --help works
    HOME=$(mktemp -d) $out/bin/qmd --help | grep -q "Usage:"
    # Test actual database initialization (requires sqlite extension loading)
    HOME=$(mktemp -d) $out/bin/qmd status
    runHook postInstallCheck
  '';

  passthru.category = "Utilities";

  meta = with lib; {
    description = "mini cli search engine for your docs, knowledge bases, meeting notes, whatever. Tracking current sota approaches while being all local";
    homepage = "https://github.com/tobi/qmd";
    license = licenses.mit;
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
    maintainers = with flake.lib.maintainers; [ mulatta ];
    platforms = lib.platforms.unix;
    mainProgram = "qmd";
  };
}
