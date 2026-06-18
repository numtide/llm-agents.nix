{
  lib,
  stdenv,
  fetchFromGitHub,
  rustPlatform,
  pkg-config,
  openssl,
  libcap,
  mkRustyV8Archive,
  versionData ? builtins.fromJSON (builtins.readFile ./hashes.json),
  version ? versionData.version,
  hash ? versionData.hash,
  src ? fetchFromGitHub {
    owner = "zed-industries";
    repo = "codex-acp";
    rev = "v${version}";
    inherit hash;
  },
  sourceRoot ? "source",
  cargoVendor ? {
    cargoHash = versionData.cargoHash;
  },
  codexOwner ? versionData.codexOwner,
  codexRev ? versionData.codexRev,
  codexSrcHash ? versionData.codexSrcHash,
  codexSrc ? fetchFromGitHub {
    owner = codexOwner;
    repo = "codex";
    rev = codexRev;
    hash = codexSrcHash;
  },
  codexBwrapSourceDir ? "${codexSrc}/codex-rs/vendor/bubblewrap",
  librusty_v8 ? mkRustyV8Archive versionData.librusty_v8,
}:
rustPlatform.buildRustPackage (
  {
    pname = "codex-acp";
    inherit version src sourceRoot;

    env = {
      RUSTY_V8_ARCHIVE = librusty_v8;
    }
    // lib.optionalAttrs stdenv.hostPlatform.isLinux {
      # Point the codex-linux-sandbox build.rs at the vendored bubblewrap source
      CODEX_BWRAP_SOURCE_DIR = codexBwrapSourceDir;
    };

    nativeBuildInputs = [
      pkg-config
    ];

    buildInputs = [
      openssl
    ]
    ++ lib.optionals stdenv.hostPlatform.isLinux [
      libcap
    ];

    doCheck = false;

    passthru = {
      category = "ACP Ecosystem";
      inherit mkRustyV8Archive;
      inherit librusty_v8;
    };

    meta = with lib; {
      description = "An ACP-compatible coding agent powered by Codex";
      homepage = "https://github.com/zed-industries/codex-acp";
      changelog = "https://github.com/zed-industries/codex-acp/releases/tag/v${version}";
      license = licenses.asl20;
      maintainers = with maintainers; [ ];
      platforms = platforms.unix;
      sourceProvenance = with sourceTypes; [
        fromSource
        binaryNativeCode
      ];
      mainProgram = "codex-acp";
    };
  }
  // cargoVendor
)
