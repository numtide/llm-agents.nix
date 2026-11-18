{
  lib,
  stdenv,
  fetchFromGitHub,
  rustPlatform,
  perl,
  pkg-config,
}:

rustPlatform.buildRustPackage (finalAttrs: {
  pname = "kitesurf";
  version = "2026.11.9";

  src = fetchFromGitHub {
    owner = "cloudflare";
    repo = "kitesurf";
    tag = finalAttrs.version;
    hash = "sha256-GIJuGlLqycvWp8bMmNX/QtE9JVpmwSaNDmY0hyLJvJY=";
  };

  sourceRoot = "${finalAttrs.src.name}/packages/kitesurf-cli";

  cargoHash = "sha256-5wfCrn/+8zN817XrdxzNp2RDWIYuSDD2BoyZZND5NkU=";

  nativeBuildInputs = lib.optionals stdenv.hostPlatform.isLinux [
    perl
    pkg-config
  ];

  checkFlags = map (t: "--skip=${t}") [
    # These load the engine's scene-host Wasm, which upstream builds with Bazel outside this crate.
    "font_cache::tests::duplicate_hashes_for_one_font_path_fetch_and_resolve_once"
    "playback::tests::partial_replay_composites_without_a_display_and_recovers_a_lost_base"
    "playback::tests::partial_replay_preserves_full_rgba_dimensions_and_terminal_placement"
    "playback::tests::retained_replay_reports_corrupt_full_scenes"
    "wasm::tests::cropped_partial_returns_only_the_requested_png_rectangle"
    "wasm::tests::downloaded_module_runs_without_js_imports"
    "wasm::tests::retained_frame_rejects_truncated_headers_without_losing_its_base"
    "wasm::tests::retained_frame_replaces_pixels_and_clamps_patch_edges"
    "wasm::tests::retained_frame_requires_its_exact_base_and_recovers_after_failure"
    # Wall-clock deadline assertion that is flaky on loaded builders.
    "wasm::tests::a_spinning_guest_call_is_interrupted"
  ];

  # The binary reports the crate version, which upstream does not bump with each repository tag.
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    $out/bin/kitesurf --version | grep -q '^kitesurf '
    runHook postInstallCheck
  '';

  passthru.category = "Utilities";

  meta = {
    description = "Terminal client for Kitesurf, an experimental browser engine that runs on Cloudflare Workers";
    homepage = "https://kitesurf.dev/";
    changelog = "https://github.com/cloudflare/kitesurf/releases/tag/${finalAttrs.version}";
    license = lib.licenses.asl20;
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
    maintainers = with lib.maintainers; [ ryoppippi ];
    mainProgram = "kitesurf";
    platforms = lib.platforms.unix;
  };
})
