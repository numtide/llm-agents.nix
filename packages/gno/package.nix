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

  version = "0.16.0";

  src = fetchFromGitHub {
    owner = "gmickel";
    repo = "gno";
    tag = "v${version}";
    hash = "sha256-PPTjQNFABtAosfF6lTwxN14ce2SsbKNG0tXWS6vBLrI=";
  };

  # Add package-lock.json (upstream uses bun.lockb)
  postPatch = ''
    cp ${./package-lock.json} package-lock.json
  '';
in
buildNpmPackage {
  inherit
    npmConfigHook
    version
    src
    postPatch
    ;
  pname = "gno";

  npmDeps = fetchNpmDepsWithPackuments {
    inherit src postPatch;
    name = "gno-${version}-npm-deps";
    hash = "sha256-I/DJNIpFoYEWF1CZflG2zW4h9iH66PMLu1qK6aGA1XU=";
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
  autoPatchelfIgnoreMissingDeps = [
    # musl (we use glibc)
    "libc.musl-x86_64.so.1"
    "libc.musl-aarch64.so.1"
    # Prebuilt binaries target CUDA 13 but we provide CUDA 12 (ABI compatible)
    # libcuda.so.1 comes from nvidia driver (autoAddDriverRunpath)
    "libcudart.so.13"
    "libcublas.so.13"
    "libcuda.so.1"
  ]
  # CUDA 12 libs — only ignore when CUDA is disabled (otherwise provided by cudaPackages)
  ++ lib.optionals (!effectiveCudaSupport) [
    "libcudart.so.12"
    "libcublas.so.12"
  ]
  ++ lib.optionals (!effectiveVulkanSupport) [
    "libvulkan.so.1"
  ];

  # Skip any build scripts since this is a TypeScript project run with bun
  npmFlags = [
    "--ignore-scripts"
    "--legacy-peer-deps"
  ];

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

      mkdir -p $out/lib/gno $out/bin

      cp -r node_modules src package.json $out/lib/gno/

      # Patch detectGlibc.js to always return true on Linux
      # node-llama-cpp checks FHS paths (/lib, /usr/lib) for glibc which don't exist on NixOS
      # Without this patch, it falls back to building llama.cpp which fails in read-only store
      patch -p1 -d $out/lib/gno < ${./node-llama-cpp-detectGlibc.patch}

      makeWrapper ${bun}/bin/bun $out/bin/gno \
        --add-flags "$out/lib/gno/src/index.ts" \
        --set DYLD_LIBRARY_PATH "${sqlite.out}/lib" \
        --set LD_LIBRARY_PATH "${ldLibraryPath}"

      runHook postInstall
    '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    # Test --help works
    HOME=$(mktemp -d) $out/bin/gno --help | grep -qi "gno"
    runHook postInstallCheck
  '';

  passthru.category = "Utilities";

  meta = with lib; {
    description = "Local-first knowledge engine with hybrid search, RAG Q&A, and MCP server integration";
    homepage = "https://github.com/gmickel/gno";
    license = licenses.mit;
    sourceProvenance = with lib.sourceTypes; [
      fromSource
      binaryNativeCode
    ];
    maintainers = with flake.lib.maintainers; [ afterthought ];
    platforms = lib.platforms.unix;
    mainProgram = "gno";
  };
}
