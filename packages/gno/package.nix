{
  lib,
  stdenv,
  fetchFromGitHub,
  fetchurl,
  mkUpdater,
  bun,
  bun2nixLib,
  makeWrapper,
  sqlite,
  formatelf,
  flake,
  libarchive,
  runCommandLocal,
  glibcLocales ? null,

  # GPU support
  config,
  cudaSupport ? config.cudaSupport or false,
  cudaPackages ? { },
  vulkanSupport ? stdenv.hostPlatform.isLinux,
  vulkan-loader,
  autoAddDriverRunpath,
}:
let
  # CUDA only supported on x86_64-linux
  effectiveCudaSupport = cudaSupport && stdenv.hostPlatform.isLinux && stdenv.hostPlatform.isx86_64;
  # Vulkan supported on all Linux
  effectiveVulkanSupport = vulkanSupport && stdenv.hostPlatform.isLinux;

  versionData = builtins.fromJSON (builtins.readFile ./hashes.json);
  inherit (versionData) version hash;

  # Work around bsdtar failing on non-ASCII filenames in the Nix sandbox (LANG=C).
  # @fastify/send contains "test/fixtures/snow ☃/index.html" which triggers:
  #   "bsdtar: Pathname can't be converted from UTF-8 to current locale."
  # We override this package to extract it with proper locale settings,
  # bypassing bun2nix's default extractPackage which lacks locale support.
  bunPackages = import ./bun.nix { inherit fetchurl; };
  fastifySendAttr = lib.findFirst (lib.hasPrefix "@fastify/send@") null (
    builtins.attrNames bunPackages
  );

  mkFastifySendOverride =
    tgz: _prev:
    runCommandLocal "fastify-send-utf8-extract"
      {
        nativeBuildInputs = [ libarchive ] ++ lib.optionals stdenv.hostPlatform.isLinux [ glibcLocales ];
      }
      (
        let
          # On Linux, LOCALE_ARCHIVE + LC_ALL=C.UTF-8 are required for bsdtar UTF-8 support.
          # On macOS, just LANG=en_US.UTF-8 suffices (no locale archive needed).
          localeEnv =
            if stdenv.hostPlatform.isLinux then
              ''
                export LOCALE_ARCHIVE="${glibcLocales}/lib/locale/locale-archive"
                export LC_ALL=C.UTF-8
              ''
            else
              ''
                export LANG=en_US.UTF-8
              '';
        in
        ''
          ${localeEnv}
          mkdir -p $out
          bsdtar --extract \
            --file "${tgz}" \
            --directory "$out" \
            --strip-components=1 \
            --no-same-owner \
            --no-same-permissions
          chmod -R u+rwx $out
        ''
      );

  fastifySendOverrides =
    assert
      fastifySendAttr != null
      || throw "gno: @fastify/send not found in bun.nix — the UTF-8 locale override needs updating";
    {
      ${fastifySendAttr} = mkFastifySendOverride bunPackages.${fastifySendAttr};
    };
in
stdenv.mkDerivation {
  inherit version;
  pname = "gno";

  src = fetchFromGitHub {
    owner = "gmickel";
    repo = "gno";
    tag = "v${version}";
    inherit hash;
  };

  nativeBuildInputs = [
    bun2nixLib.hook
    makeWrapper
  ]
  ++ lib.optionals stdenv.hostPlatform.isLinux [ formatelf ]
  ++ lib.optionals effectiveCudaSupport [ autoAddDriverRunpath ];

  buildInputs = [
    sqlite
  ]
  ++ lib.optionals stdenv.hostPlatform.isLinux [
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

  bunDeps = bun2nixLib.fetchBunDeps {
    bunNix = ./bun.nix;
    overrides = fastifySendOverrides;
  };

  # No build step needed - we'll run directly with bun
  # bun >= 1.4.4 names remote-tarball cache entries after the lockfile's
  # integrity; bun2nix still names them after the URL, so link the new name.
  postBunSetInstallCacheDirPhase = ''
    old=("$BUN_INSTALL_CACHE_DIR"/@T@*@@@1)
    if [ ''${#old[@]} -ne 1 ]; then
      echo "expected exactly one tarball cache entry (xlsx), got: ''${old[*]}" >&2
      exit 1
    fi
    sri=$(sed -n 's/.*"xlsx@https:.*"sha512-\([^"]*\)".*/\1/p' bun.lock)
    hex=$(printf '%s' "$sri" | base64 -d | head -c 16 | od -An -tx1 | tr -d ' \n')
    ln -s "$old" "$BUN_INSTALL_CACHE_DIR/@T@sha512-$hex@@@1"
  '';

  dontUseBunBuild = true;
  dontUseBunInstall = true;
  # Skip lifecycle scripts (lefthook install requires git which isn't needed at build time)
  dontRunLifecycleScripts = true;

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

      cp -r node_modules src vendor package.json $out/lib/gno/

      # Patch detectGlibc.js to always return true on Linux
      # node-llama-cpp checks FHS paths (/lib, /usr/lib) for glibc which don't exist on NixOS
      # Without this patch, it falls back to building llama.cpp which fails in read-only store
      patch -p1 -d $out/lib/gno < ${../../patches/node-llama-cpp-detectGlibc.patch}

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

  passthru.category = "Memory & Code Intelligence";
  passthru.updater = mkUpdater {
    kind = "bun-github";
    purl = "pkg:github/gmickel/gno";
  };

  meta = with lib; {
    description = "Local-first knowledge engine with hybrid search, RAG Q&A, and MCP server integration";
    homepage = "https://github.com/gmickel/gno";
    changelog = "https://github.com/gmickel/gno/releases/tag/v${version}";
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
