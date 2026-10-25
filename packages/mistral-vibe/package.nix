{
  lib,
  stdenv,
  python3,
  fetchPypi,
  fetchurl,
  callPackage,
  rustPlatform,
  cargo,
  rustc,
  maturin,
  formatelf,
  versionCheckHook,
  versionCheckHomeHook,
  mkUpdater,
}:

let
  versionData = builtins.fromJSON (builtins.readFile ./hashes.json);
  inherit (versionData) version hashes;

  wheelPlatforms = {
    x86_64-linux = "manylinux_2_28_x86_64";
    aarch64-linux = "manylinux_2_28_aarch64";
    aarch64-darwin = "macosx_11_0_arm64";
  };

  wheelUrl = "https://files.pythonhosted.org/packages/cp312/m/mistral_vibe/mistral_vibe-{version}-cp312-abi3-{platform}.whl";

  textual-speedups = python3.pkgs.buildPythonPackage rec {
    pname = "textual-speedups";
    version = "0.2.1";
    pyproject = true;

    src = fetchPypi {
      pname = "textual_speedups";
      inherit version;
      hash = "sha256-cs8Pe97t4BU2e1m3C89yS6LDCAqGQevF65SzatFTaCQ=";
    };

    cargoDeps = rustPlatform.fetchCargoVendor {
      inherit src;
      name = "${pname}-${version}";
      hash = "sha256-Bz4ocEziOlOX4z5F9EDry99YofeGyxL/6OTIf/WEgK4=";
    };

    nativeBuildInputs = [
      rustPlatform.cargoSetupHook
      rustPlatform.maturinBuildHook
      cargo
      rustc
      maturin
    ];

    pythonImportsCheck = [ "textual_speedups" ];

    meta = with lib; {
      description = "Optional Rust speedups for Textual TUI framework";
      homepage = "https://github.com/willmcgugan/textual-speedups";
      license = licenses.mit;
      sourceProvenance = with sourceTypes; [ fromSource ];
      platforms = platforms.all;
    };
  };

  tree-sitter-bash = python3.pkgs.buildPythonPackage rec {
    pname = "tree-sitter-bash";
    version = "0.25.1";
    pyproject = true;

    src = fetchPypi {
      pname = "tree_sitter_bash";
      inherit version;
      hash = "sha256-v8C9qne8HobjxmUuWm4UDEDAoWuEGFwrY6182Am4jxQ=";
    };

    build-system = with python3.pkgs; [
      setuptools
    ];

    pythonImportsCheck = [ "tree_sitter_bash" ];

    meta = with lib; {
      description = "Bash grammar for tree-sitter";
      homepage = "https://github.com/tree-sitter/tree-sitter-bash";
      license = licenses.mit;
      sourceProvenance = with sourceTypes; [ fromSource ];
      platforms = platforms.all;
    };
  };

  python = python3.override {
    self = python;
    packageOverrides = _pyfinal: pyprev: {
      inherit textual-speedups tree-sitter-bash;

      # vibe uses DEFAULT_THEME="ansi-dark", a built-in theme added in
      # textual >=8.2.5; older textual crashes at startup with InvalidThemeError.
      textual = pyprev.textual.overridePythonAttrs (old: rec {
        version = "8.2.7";
        src = old.src.override {
          tag = "v${version}";
          hash = "sha256-jRTdxVpeRk8gAur5+VpLVVghBdYenXysoEFRBfczkR4=";
        };
      });

      # vibe imports deep_update from pydantic_settings.sources.base, a
      # re-export added in 2.13.
      pydantic-settings = pyprev.pydantic-settings.overridePythonAttrs (_: rec {
        version = "2.14.2";
        src = fetchPypi {
          pname = "pydantic_settings";
          inherit version;
          hash = "sha256-wZ3WSxkJfx3oAYTwzHsCcqE65uFwy/JAo+J+OB7RSl8=";
        };
      });

      # Build mistralai/acp in this set so they link the overridden otel
      # packages; stock python3.pkgs would drag old otel into the closure.
      mistralai = callPackage ./mistralai.nix { python3 = python; };
      agent-client-protocol = callPackage ./agent-client-protocol.nix { python3 = python; };

    };
  };

in
python.pkgs.buildPythonApplication {
  pname = "mistral-vibe";
  inherit version;
  format = "wheel";

  src = fetchurl {
    url =
      builtins.replaceStrings
        [ "{version}" "{platform}" ]
        [
          version
          wheelPlatforms.${stdenv.hostPlatform.system}
        ]
        wheelUrl;
    hash = hashes.${stdenv.hostPlatform.system};
  };

  nativeBuildInputs = lib.optionals stdenv.hostPlatform.isLinux [ formatelf ];
  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [ stdenv.cc.cc.lib ];

  dependencies = with python.pkgs; [
    agent-client-protocol
    anyio
    cachetools
    croniter
    cryptography
    gitpython
    giturlparse
    google-auth
    httpx
    httpx-sse
    humanize
    jsonpatch
    keyring
    markdownify
    mcp
    miniaudio
    mistralai
    opentelemetry-api
    opentelemetry-exporter-otlp-proto-http
    opentelemetry-sdk
    opentelemetry-semantic-conventions
    packaging
    pexpect
    pydantic
    pydantic-settings
    pyperclip
    python-dotenv
    pyyaml
    requests
    rfc8785
    rich
    sentry-sdk
    setproctitle
    sounddevice
    textual
    textual-speedups
    tomli-w
    tree-sitter
    tree-sitter-bash
    truststore
    watchfiles
    websockets
    zstandard
  ];

  # Upstream pins the whole dependency closure with `==`; overrides above still
  # satisfy the otel requirements (issue #3668).
  pythonRelaxDeps = true;

  # `import vibe` alone is lazy and misses dependency drift: mistralai 2.1.3
  # lacked mistralai.extra.observability.telemetry yet built fine and crashed
  # at runtime (issue #6462). Import submodules that pull in the vendored deps
  # so drift fails the build.
  pythonImportsCheck = [
    "vibe"
    "vibe.acp.entrypoint"
    "vibe.app_server.stdio"
    "vibe.app_server.local"
    "vibe.core.llm.backend.mistral"
    "vibe.cli.transcribe.mistral_transcribe_client"
  ];

  doInstallCheck = true;
  nativeInstallCheckInputs = [
    versionCheckHook
    versionCheckHomeHook
  ];
  versionCheckProgramArg = [ "--version" ];

  passthru = {
    category = "AI Coding Agents";
    updater = mkUpdater {
      kind = "platform";
      versionSource = {
        type = "json";
        url = "https://pypi.org/pypi/mistral-vibe/json";
        pointer = "/info/version";
      };
      urlTemplate = wheelUrl;
      platforms = wheelPlatforms;
    };
  };

  meta = with lib; {
    description = "Minimal CLI coding agent by Mistral AI - open-source command-line coding assistant powered by Devstral";
    homepage = "https://github.com/mistralai/mistral-vibe";
    changelog = "https://github.com/mistralai/mistral-vibe/releases/tag/v${version}";
    license = licenses.asl20;
    sourceProvenance = with sourceTypes; [
      fromSource
      binaryNativeCode
    ];
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
      "aarch64-darwin"
    ];
    mainProgram = "vibe";
  };
}
