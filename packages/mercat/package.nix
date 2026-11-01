{
  lib,
  stdenv,
  flake,
  fetchFromGitHub,
  zig_0_17,
  versionCheckHook,
  versionCheckHomeHook,
}:

let
  zig = zig_0_17;
in
stdenv.mkDerivation (finalAttrs: {
  pname = "mercat";
  version = "0.3.7";

  src = fetchFromGitHub {
    owner = "tawago";
    repo = "mercat";
    tag = "v${finalAttrs.version}";
    hash = "sha256-8yXh8yZtbQ/iejyHPCWUf7uuG4jpeF9IfMquxAAbbak=";
  };

  # All of mercat's dependencies (koino, vaxis, uucode) are lazy, so fetch
  # them all up front for the offline sandbox build.
  zigDeps = zig.fetchDeps {
    inherit (finalAttrs) src pname version;
    fetchAll = true;
    hash = "sha256-UvqzvJ6uva7xiZGTpBoBguyT9Jl0Odx/FGdIBLzmGkQ=";
  };

  nativeBuildInputs = [ zig.hook ];

  postConfigure = ''
    ln -s ${finalAttrs.zigDeps} "$ZIG_GLOBAL_CACHE_DIR/p"
  '';

  zigBuildFlags = [ "-Doptimize=ReleaseFast" ];

  # Upstream's `zig build test` reports failed test binaries in the sandbox
  # without failing the phase, so it gives no usable signal; the install
  # checks below exercise the built binary instead.
  doCheck = false;

  doInstallCheck = true;
  nativeInstallCheckInputs = [
    versionCheckHook
    versionCheckHomeHook
  ];

  postInstallCheck = ''
    printf 'flowchart LR\n  A-->B\n' | HOME="$TMPDIR" "$out/bin/mercat" > diagram.txt
    cat diagram.txt
    grep -q A diagram.txt
    grep -q B diagram.txt
  '';

  passthru.category = "Utilities";

  meta = {
    description = "Render markdown and mermaid diagrams in the terminal";
    homepage = "https://github.com/tawago/mercat";
    changelog = "https://github.com/tawago/mercat/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.gpl3Plus;
    sourceProvenance = [ lib.sourceTypes.fromSource ];
    maintainers = with flake.lib.maintainers; [ imkarrer ];
    mainProgram = "mercat";
    platforms = lib.platforms.linux ++ lib.platforms.darwin;
  };
})
