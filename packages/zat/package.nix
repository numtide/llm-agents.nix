{
  lib,
  flake,
  rustPlatform,
  fetchFromGitHub,
}:

rustPlatform.buildRustPackage (finalAttrs: {
  pname = "zat";
  version = "0.5.4";

  src = fetchFromGitHub {
    owner = "bglgwyng";
    repo = "zat";
    tag = "v${finalAttrs.version}";
    hash = "sha256-HFFVsfbT5syDxKO8ECPBIHqzJxIKAvp7X7O7Cji2Sxk=";
  };

  cargoHash = "sha256-VSu68KPkoOLyva+A3+TtdTg48xZg0LNenMq+z9xoAVU=";

  # The grammar crates vendor a tree-sitter array.h from before 0.26.4 whose
  # (Array *) casts violate strict aliasing. gcc 16 turns that into heap
  # corruption in the haskell scanner.
  # https://github.com/tree-sitter/tree-sitter-haskell/issues/144
  env.NIX_CFLAGS_COMPILE = "-fno-strict-aliasing";

  # Smoke test: zat has no --version flag, so run it against its own source.
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    $out/bin/zat src/main.rs > /dev/null
    runHook postInstallCheck
  '';

  passthru.category = "Memory & Code Intelligence";

  meta = {
    description = "Code outline viewer for LLM coding agents — shows exported symbols with line numbers";
    homepage = "https://github.com/bglgwyng/zat";
    changelog = "https://github.com/bglgwyng/zat/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.gpl3Only;
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
    maintainers = with flake.lib.maintainers; [ mic92 ];
    mainProgram = "zat";
    platforms = lib.platforms.unix;
  };
})
