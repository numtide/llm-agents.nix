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
  version = "0.1.0-unstable-20261122-6dcf4cc";

  src = fetchFromGitHub {
    owner = "LilithSemi";
    repo = "chock";
    tag = finalAttrs.version;
    hash = "sha256-fkp2nIvFSc9jSSdC2Sbxc/53NUR6gWYCW7emxRRJKAQ=";
  };

  zigDeps = zig.fetchDeps {
    inherit (finalAttrs) src pname version;
    hash = "sha256-glNxj80FPfvE7PNeyKQEUfPQV4gR1zyPiPhiblIKwxw=";
  };

  nativeBuildInputs = [
    zig
    git
    typescript
  ];

  # the build dir is too long for a unix socket path in the darwin sandbox;
  # curl 8.23 makes git re-ask for the URL's username, which askpass ignores
  postPatch = ''
    substituteInPlace lib/chock-broker/handover.zig \
      --replace-fail 'const endpoint = try Endpoint.open(io, paths, null);' \
        'if (paths.socket.len > socket.max_socket_path) return error.SkipZigTest;
         const endpoint = try Endpoint.open(io, paths, null);'
    substituteInPlace test/broker/git_push.zig \
      --replace-fail 'const git_path = @import("chock_path").git_path;' 'const git_path = "";'
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
