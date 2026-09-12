{
  lib,
  python3,
  fetchFromGitHub,
  fetchPypi,
  callPackage,
  rustPlatform,
  cargo,
  rustc,
  maturin,
  versionCheckHook,
  versionCheckHomeHook,
}:

let
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

  # mistral-vibe >=2.6 needs opentelemetry-semantic-conventions>=0.60b1
  # (GEN_AI_PROVIDER_NAME, issue #3668); nixpkgs ships 0.55b0. The otel stack is
  # a lockstep monorepo, so bumping opentelemetry-api's src bumps everything.
  otelVersion = "1.40.0";
  otelContribVersion = "0.61b0";
  otelSrc = fetchFromGitHub {
    owner = "open-telemetry";
    repo = "opentelemetry-python";
    tag = "v${otelVersion}";
    hash = "sha256-1KVy9s+zjlB4w7E45PMCWRxPus24bgBmmM3k2R9d+Jg=";
  };
  otelContribSrc = fetchFromGitHub {
    owner = "open-telemetry";
    repo = "opentelemetry-python-contrib";
    tag = "v${otelContribVersion}";
    hash = "sha256-DT13gcYPNYXBPnf622WsA16C+7sabJfOshDquHn06Ok=";
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

      opentelemetry-api = pyprev.opentelemetry-api.overridePythonAttrs (_: {
        version = otelVersion;
        src = otelSrc;
        sourceRoot = "${otelSrc.name}/opentelemetry-api";
      });

      # 1.40.0 added timing-sensitive tests that flake on loaded builders.
      opentelemetry-exporter-otlp-proto-http =
        pyprev.opentelemetry-exporter-otlp-proto-http.overridePythonAttrs
          (old: {
            disabledTests = (old.disabledTests or [ ]) ++ [
              "test_retry_timeout"
              "test_shutdown_interrupts_retry_backoff"
            ];
          });

      opentelemetry-instrumentation = pyprev.opentelemetry-instrumentation.overridePythonAttrs (_: {
        version = otelContribVersion;
        src = otelContribSrc;
        sourceRoot = "${otelContribSrc.name}/opentelemetry-instrumentation";
      });

      # Set explicitly: nixpkgs inherits this from opentelemetry-instrumentation,
      # but overridePythonAttrs won't re-evaluate that reference.
      opentelemetry-semantic-conventions =
        pyprev.opentelemetry-semantic-conventions.overridePythonAttrs
          (_: {
            version = otelContribVersion;
          });
    };
  };
in
python.pkgs.buildPythonApplication rec {
  pname = "mistral-vibe";
  version = "2.25.4";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "mistralai";
    repo = "mistral-vibe";
    tag = "v${version}";
    hash = "sha256-v+Pl15r32DaB/+Yo1zKvMP1iFmC1q111s16KNpWLanI=";
  };

  build-system = with python.pkgs; [
    hatchling
    hatch-vcs
    editables
  ];

  # Upstream pins exact build-backend versions (hatchling==x.y.z); strip the
  # pins so the nixpkgs-provided versions satisfy pypa build.
  postPatch = ''
    substituteInPlace pyproject.toml \
      --replace-fail 'requires = ["hatchling==1.31.0", "hatch-vcs==0.5.0", "editables==0.6"]' \
        'requires = ["hatchling", "hatch-vcs", "editables"]'
  '';

  dependencies = with python.pkgs; [
    agent-client-protocol
    anyio
    cachetools
    cryptography
    gitpython
    giturlparse
    google-auth
    httpx
    humanize
    jsonpatch
    keyring
    markdownify
    mcp
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
    "vibe.cli.cli"
    "vibe.core.llm.backend.mistral"
    "vibe.cli.transcribe.mistral_transcribe_client"
  ];

  doInstallCheck = true;
  nativeInstallCheckInputs = [
    versionCheckHook
    versionCheckHomeHook
  ];
  versionCheckProgramArg = [ "--version" ];

  passthru.category = "AI Coding Agents";

  meta = with lib; {
    description = "Minimal CLI coding agent by Mistral AI - open-source command-line coding assistant powered by Devstral";
    homepage = "https://github.com/mistralai/mistral-vibe";
    changelog = "https://github.com/mistralai/mistral-vibe/releases/tag/v${version}";
    license = licenses.asl20;
    sourceProvenance = with sourceTypes; [ fromSource ];
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
      "aarch64-darwin"
    ];
    mainProgram = "vibe";
  };
}
