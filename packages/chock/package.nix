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
  version = "0.1.0-unstable-20261023-4be5b3b";

  src = fetchFromGitHub {
    owner = "LilithSemi";
    repo = "chock";
    tag = finalAttrs.version;
    hash = "sha256-+yTQTXyghIvsgtJaF+Qio1GWeH9SfwreVRoh8J5TU/Q=";
  };

  zigDeps = zig.fetchDeps {
    inherit (finalAttrs) src pname version;
    hash = "sha256-vrWdMPat6GnymTJgHoxFKuN4j7JTAm+cjYZk/ygzaQE=";
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
    changelog = "https://github.com/LilithSemi/chock/releases/tag/${finalAttrs.version}";
    license = lib.licenses.asl20;
    sourceProvenance = [ lib.sourceTypes.fromSource ];
    maintainers = with lib.maintainers; [ RossComputerGuy ];
    mainProgram = "chock";
    platforms = lib.platforms.linux ++ lib.platforms.darwin;
  };
})
