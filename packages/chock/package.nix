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
  version = "0.1.0-unstable-20261114-f683646";

  src = fetchFromGitHub {
    owner = "LilithSemi";
    repo = "chock";
    tag = finalAttrs.version;
    hash = "sha256-s0JDfsxr5cwu1XFsbkdrANnsND6C5s+IO2+3b1esNJU=";
  };

  zigDeps = zig.fetchDeps {
    inherit (finalAttrs) src pname version;
    hash = "sha256-EKB48hSspw5yy/Mzh0gsM94TH7YYhnLkDkrgVGwjzP8=";
  };

  nativeBuildInputs = [
    zig
    git
    typescript
  ];

  # the build dir is too long for a unix socket path in the darwin sandbox
  postPatch = ''
    substituteInPlace lib/chock-broker/handover.zig \
      --replace-fail 'const endpoint = try Endpoint.open(io, paths, null);' \
        'if (paths.socket.len > socket.max_socket_path) return error.SkipZigTest;
         const endpoint = try Endpoint.open(io, paths, null);'
  '';

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
