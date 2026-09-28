{
  lib,
  flake,
  stdenv,
  fetchFromGitHub,
  cmake,
  ninja,
  pkg-config,
  openssl,
  nghttp2,
  nlohmann_json,
  simdjson,
  versionCheckHook,
  versionCheckHomeHook,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "agentty";
  version = "0.9.11";

  src = fetchFromGitHub {
    owner = "1ay1";
    repo = "agentty";
    tag = "v${finalAttrs.version}";
    hash = "sha256-2chfAJPzEKCqnX2YnyXrvhICeEF9+KUKp0jFN0xl8cc=";
    fetchSubmodules = true;
  };

  nativeBuildInputs = [
    cmake
    ninja
    pkg-config
  ];

  buildInputs = [
    openssl
    nghttp2
    nlohmann_json
    simdjson
  ];

  cmakeFlags = [
    # Resolve FetchContent deps (nlohmann_json, simdjson) from buildInputs.
    (lib.cmakeFeature "FETCHCONTENT_TRY_FIND_PACKAGE_MODE" "ALWAYS")
    (lib.cmakeBool "AGENTTY_USE_MIMALLOC" false)
    # maya defaults to -march=native.
    (lib.cmakeBool "MAYA_NATIVE_TUNING" false)
  ];

  # No install() rules upstream.
  installPhase = ''
    runHook preInstall
    install -Dm755 agentty $out/bin/agentty
    runHook postInstall
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [
    versionCheckHook
    versionCheckHomeHook
  ];

  passthru.category = "AI Coding Agents";

  meta = {
    description = "Terminal AI pair programmer written in C++";
    homepage = "https://github.com/1ay1/agentty";
    changelog = "https://github.com/1ay1/agentty/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.mit;
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
    maintainers = with flake.lib.maintainers; [ smdex ];
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
    mainProgram = "agentty";
  };
})
