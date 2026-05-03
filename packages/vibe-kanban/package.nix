{
  lib,
  stdenv,
  fetchFromGitHub,
  fetchurl,
  unzip,
  rustPlatform,
  pnpm_10,
  fetchPnpmDeps,
  pnpmConfigHook,
  nodejs-slim,
  pkg-config,
  openssl,
  libgit2,
  sqlite,
  llvmPackages,
}:

let
  versionData = builtins.fromJSON (builtins.readFile ./hashes.json);
  inherit (versionData)
    version
    tag
    hash
    cargoHash
    npmDepsHash
    releaseZipHash
    ;

  src = fetchFromGitHub {
    owner = "BloopAI";
    repo = "vibe-kanban";
    rev = tag;
    inherit hash;
  };

  # Upstream's release zip contains pre-built frontend assets with the
  # react-virtuoso commercial license key already baked in by their CI.
  # We extract just the key and inject it into our own source build so
  # we don't have to store it in the repository.
  releaseZip = fetchurl {
    url = "https://github.com/BloopAI/vibe-kanban/releases/download/${tag}/vibe-kanban-${tag}.zip";
    hash = releaseZipHash;
  };

  # Phase 1: Build frontend
  frontend = stdenv.mkDerivation {
    pname = "vibe-kanban-frontend";
    inherit version src;

    nativeBuildInputs = [
      nodejs-slim
      pnpm_10
      pnpmConfigHook
      unzip
    ];

    pnpmDeps = fetchPnpmDeps {
      pname = "vibe-kanban-frontend";
      inherit version src;
      pnpm = pnpm_10;
      hash = npmDepsHash;
      fetcherVersion = 2;
    };

    buildPhase = ''
      runHook preBuild

      # Extract the react-virtuoso license key from upstream's pre-built
      # release assets rather than storing it in our repository.
      export VITE_PUBLIC_REACT_VIRTUOSO_LICENSE_KEY=$(
        unzip -p ${releaseZip} '*/assets/index-*.js' \
          | grep -o 'licenseKey:"[^"]*"' \
          | head -1 \
          | cut -d'"' -f2
      )

      # v0.1.44+ moved the desktop UI into a pnpm workspace package at
      # packages/local-web. crates/server/src/routes/frontend.rs embeds
      # `../../packages/local-web/dist` via rust-embed.
      cd packages/local-web
      pnpm build
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p $out
      cp -r dist/* $out/
      runHook postInstall
    '';
  };

in
# Phase 2: Build Rust with embedded frontend
rustPlatform.buildRustPackage {
  pname = "vibe-kanban";
  inherit version src cargoHash;

  cargoBuildFlags = [
    "--package"
    "server"
    "--package"
    "review"
    "--package"
    "mcp"
  ];

  nativeBuildInputs = [
    pkg-config
    llvmPackages.libclang
  ];
  buildInputs = [
    openssl
    libgit2
    sqlite
  ];

  # Copy frontend assets before Rust build. crates/server embeds
  # ../../packages/local-web/dist via rust-embed, so the path the binary
  # expects must be populated before cargo runs.
  preBuild = ''
    mkdir -p packages/local-web/dist
    cp -r ${frontend}/* packages/local-web/dist/
  '';

  env = {
    SQLX_OFFLINE = "true";
    LIBCLANG_PATH = "${llvmPackages.libclang.lib}/lib";
    # v0.1.44+ pulls in transitive deps that activate openssl-sys'
    # `vendored` feature, which would compile OpenSSL from source via
    # the openssl-src crate (needs perl in buildInputs). Force dynamic
    # linking against the openssl already in buildInputs.
    OPENSSL_NO_VENDOR = "1";
  };

  doCheck = false;

  postInstall = ''
    mv $out/bin/server $out/bin/vibe-kanban
    # crates/mcp produces a binary already named `vibe-kanban-mcp`
    # (was `mcp_task_server` in older releases — no rename needed now).
    mv $out/bin/review $out/bin/vibe-kanban-review
    rm -f $out/bin/generate_types
    rm -rf $out/bin/*.dSYM
  '';

  passthru.category = "Workflow & Project Management";

  meta = {
    description = "Kanban board to orchestrate AI coding agents like Claude Code, Codex, and Gemini CLI";
    homepage = "https://github.com/BloopAI/vibe-kanban";
    changelog = "https://github.com/BloopAI/vibe-kanban/releases";
    license = lib.licenses.asl20;
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
    mainProgram = "vibe-kanban";
    platforms = lib.platforms.unix;
  };
}
