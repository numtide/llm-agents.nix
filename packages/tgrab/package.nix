{
  lib,
  flake,
  fetchFromGitHub,
  rustPlatform,
  pkg-config,
  aws-lc,
  zstd,
}:

rustPlatform.buildRustPackage (finalAttrs: {
  pname = "tgrab";
  version = "0.1.1";

  src = fetchFromGitHub {
    owner = "ryoppippi";
    repo = "tgrab";
    tag = "v${finalAttrs.version}";
    hash = "sha256-N5zZ6QgdDDIO7KlZsU6I7r+cgLXYKjfgYqBCzUJjXpQ=";
  };

  cargoHash = "sha256-r2IiZ2ud0ABQrmGxtqZRu2no9lQABoIKr5g0hqmjgDI=";

  nativeBuildInputs = [ pkg-config ];

  buildInputs = [
    aws-lc
    zstd
  ];

  env = {
    RUSTFLAGS = "--cfg reqwest_unstable";
    AWS_LC_SYS_USE_SYSTEM = "1";
    ZSTD_SYS_USE_PKG_CONFIG = "1";
  };

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    $out/bin/tgrab --help > /dev/null
    runHook postInstallCheck
  '';

  passthru.category = "Utilities";

  meta = {
    description = "Fetch text content from YouTube, Twitter/X, and Bluesky";
    homepage = "https://github.com/ryoppippi/tgrab";
    changelog = "https://github.com/ryoppippi/tgrab/releases";
    license = lib.licenses.mit;
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
    maintainers = with flake.lib.maintainers; [ ryoppippi ];
    mainProgram = "tgrab";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
      "aarch64-darwin"
    ];
  };
})
