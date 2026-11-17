{
  lib,
  flake,
  chromium,
  curl,
  fetchFromGitHub,
  makeWrapper,
  python3,
  rustPlatform,
  stdenv,
  versionCheckHomeHook,
  versionCheckHook,
}:

rustPlatform.buildRustPackage (finalAttrs: {
  pname = "opencode-browse";
  version = "0.1.1";

  src = fetchFromGitHub {
    owner = "anomalyco";
    repo = "browse";
    tag = "v${finalAttrs.version}";
    hash = "sha256-lvndoaUv9kKdt5Mthblm/CHS3dlICwQz2F/Y2hzrTAY=";
  };

  cargoRoot = "rust";
  buildAndTestSubdir = "rust";
  cargoHash = "sha256-Dv8bZ3qJpvGsIclV8hM7chJXuxBwqOJ51ZBcV0zSAIg=";

  cargoBuildFlags = [
    "-p"
    "browse"
  ];

  nativeBuildInputs = [ makeWrapper ];
  nativeCheckInputs = [ curl ] ++ lib.optional stdenv.hostPlatform.isLinux chromium;

  env = {
    BROWSE_VERSION = finalAttrs.version;
    BROWSE_BUILD_ID = "nix-${finalAttrs.version}";
  }
  // lib.optionalAttrs stdenv.hostPlatform.isLinux {
    BROWSE_TEST_CHROME = "${chromium}/bin/chromium";
  };

  postInstall = ''
    wrapProgram $out/bin/browse \
      --set OPENCODE_BROWSER_AUTO_UPDATE off
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [
    python3
    versionCheckHook
    versionCheckHomeHook
  ];
  versionCheckProgramArg = "--version";
  installCheckPhase = ''
    runHook preInstallCheck

    export HOME="$TMPDIR/home"
    mkdir -p "$HOME"

    version="$($out/bin/browse --version)"
    test "$version" = "${finalAttrs.version}"
    $out/bin/browse --help | grep -F "browse lets your AI agents use your real Chrome-family browser"
    $out/bin/browse tools | grep -E '^  execute +'
    $out/bin/browse tools | grep -E '^  status +'
    $out/bin/browse tools | grep -E '^  tabs +'

    python3 - "$out/bin/browse" "${finalAttrs.version}" <<'PY'
    import json
    import subprocess
    import sys

    process = subprocess.Popen(
        [sys.argv[1], "mcp"],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    request = {
        "jsonrpc": "2.0",
        "id": 1,
        "method": "initialize",
        "params": {
            "protocolVersion": "2025-06-18",
            "capabilities": {},
            "clientInfo": {"name": "nix-install-check", "version": "1"},
        },
    }
    stdout, stderr = process.communicate(json.dumps(request) + "\n", timeout=20)
    if process.returncode != 0:
        raise SystemExit(f"browse mcp failed ({process.returncode}): {stderr}")
    response = json.loads(stdout.splitlines()[0])
    assert response["id"] == 1, response
    assert response["result"]["serverInfo"] == {
        "name": "browse",
        "version": sys.argv[2],
    }, response
    PY

    runHook postInstallCheck
  '';

  passthru.category = "Utilities";

  meta = {
    description = "MCP server that lets agents use a real Chromium browser";
    homepage = "https://github.com/anomalyco/browse";
    changelog = "https://github.com/anomalyco/browse/blob/v${finalAttrs.version}/changelog/${finalAttrs.version}.md";
    license = lib.licenses.mit;
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
    maintainers = with flake.lib.maintainers; [ rrvsh ];
    mainProgram = "browse";
    platforms = lib.platforms.unix;
  };
})
