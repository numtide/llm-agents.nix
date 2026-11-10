{
  lib,
  stdenv,
  fetchFromGitHub,
  zig_0_17,
  git,
  typescript,
}:
let
  zig = zig_0_17;
in
stdenv.mkDerivation (finalAttrs: {
  pname = "chock";
  version = "0.1.0-unstable-20261106-d771f90";

  src = fetchFromGitHub {
    owner = "LilithSemi";
    repo = "chock";
    # Untagged: zig 0.17.1 support (4b02d0a) is not in a tag yet.
    rev = "d771f90bd111acfebd7ae393d113ac44fe95ca08";
    hash = "sha256-OlR2AY4uizuuHpinpxz0qXDOSum6nFH7TEMGArWnui8=";
  };

  zigDeps = zig.fetchDeps {
    inherit (finalAttrs) src pname version;
    hash = "sha256-DyTznIycyOV42TepVCqffKrmGixIJUaRONqzB+1BGz0=";
  };

  nativeBuildInputs = [
    zig
    git
    typescript
  ];

  postConfigure = ''
    ln -s ${finalAttrs.zigDeps} "$ZIG_GLOBAL_CACHE_DIR/p"
  '';

  zigBuildFlags = [
    "-Dversion=${finalAttrs.version}"
  ];

  zigCheckFlags = finalAttrs.zigBuildFlags;

  doCheck = true;

  # Needed for unit tests
  __darwinAllowLocalNetworking = finalAttrs.doCheck;

  passthru.category = "AI Coding Agents";

  meta = {
    description = "Sandbox-first AI coding harness";
    homepage = "https://chock.ws";
    changelog = "https://github.com/LilithSemi/chock/commits/${finalAttrs.src.rev}";
    license = lib.licenses.asl20;
    sourceProvenance = [ lib.sourceTypes.fromSource ];
    maintainers = with lib.maintainers; [ RossComputerGuy ];
    mainProgram = "chock";
    platforms = lib.platforms.linux ++ lib.platforms.darwin;
  };
})
