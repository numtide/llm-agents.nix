{
  lib,
  stdenv,
  fetchFromGitHub,
  zig_0_16,
  git,
}:
let
  zig = zig_0_16;
in
stdenv.mkDerivation (finalAttrs: {
  pname = "chock";
  version = "0.1.0-unstable-20261008-ba2102d";

  src = fetchFromGitHub {
    owner = "LilithSemi";
    repo = "chock";
    tag = finalAttrs.version;
    hash = "sha256-xpdVam+gLRozKvvgHyWv5Gloy/+/25i3yalA+/vr0jM=";
  };

  zigDeps = zig.fetchDeps {
    inherit (finalAttrs) src pname version;
    hash = "sha256-SMH157bVjVgmGhaJ1Net44c3NoWNxaYRAEBH+VP3DA0=";
  };

  nativeBuildInputs = [
    zig
    git
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
    changelog = "https://github.com/LilithSemi/chock/releases/tag/${finalAttrs.version}";
    license = lib.licenses.asl20;
    sourceProvenance = [ lib.sourceTypes.fromSource ];
    maintainers = with lib.maintainers; [ RossComputerGuy ];
    mainProgram = "chock";
    platforms = lib.platforms.linux ++ lib.platforms.darwin;
  };
})
