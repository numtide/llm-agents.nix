{
  lib,
  rustPlatform,
  fetchFromGitHub,
  pkg-config,
  makeWrapper,
  versionCheckHook,
  gitMinimal,
  openssl,
  zlib,
  versionData ? builtins.fromJSON (builtins.readFile ./hashes.json),
}:

rustPlatform.buildRustPackage rec {
  pname = "sem";
  inherit (versionData) version cargoHash;

  src = fetchFromGitHub {
    owner = "Ataraxy-Labs";
    repo = "sem";
    tag = "v${version}";
    hash = versionData.hash;
  };

  cargoRoot = "crates";

  nativeBuildInputs = [
    makeWrapper
    pkg-config
  ];

  buildInputs = [
    openssl
    zlib
  ];

  buildAndTestSubdir = cargoRoot;

  cargoBuildFlags = [
    "--package"
    "sem-cli"
    "--no-default-features"
  ];

  cargoTestFlags = cargoBuildFlags;

  # The upstream test suite creates many temporary git repositories and is
  # expensive; the install check below verifies the packaged CLI starts and
  # reports the expected version.
  doCheck = false;

  postInstall = ''
    wrapProgram $out/bin/sem \
      --argv0 sem \
      --set-default SEM_NO_TELEMETRY 1 \
      --prefix PATH : ${lib.makeBinPath [ gitMinimal ]}
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [ versionCheckHook ];
  versionCheckProgramArg = [ "--version" ];

  passthru.category = "Code Review";

  meta = with lib; {
    description = "Semantic version control CLI built on Git";
    homepage = "https://github.com/Ataraxy-Labs/sem";
    changelog = "https://github.com/Ataraxy-Labs/sem/releases/tag/v${version}";
    license = with licenses; [
      mit
      asl20
    ];
    sourceProvenance = with sourceTypes; [ fromSource ];
    maintainers = with maintainers; [ nwjsmith ];
    platforms = platforms.unix;
    mainProgram = "sem";
  };
}
