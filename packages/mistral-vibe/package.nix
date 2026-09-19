{
  lib,
  flake,
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

      # The harness wheel (below) enforces certifi>=2026.7.22 via
      # pythonRuntimeDepsCheck; nixpkgs ships 2026.6.17.
      certifi = pyprev.certifi.overridePythonAttrs (_: rec {
        version = "2026.7.22";
        src = fetchPypi {
          pname = "certifi";
          inherit version;
          hash = "sha256-dB4sOzUd3xaac42p8sBIYI/38sXMAvHrxrEYuwkNXVU=";
        };
      });

      # The h2 cancellation tests race a 10ms anyio window and flake on
      # loaded builders.
      httpcore2 = pyprev.httpcore2.overridePythonAttrs (old: {
        disabledTests = (old.disabledTests or [ ]) ++ [
          "test_h2_timeout_during_handshake"
          "test_h2_timeout_during_request"
          "test_h2_timeout_during_response"
        ];
      });

      # watchfiles' test suite needs real filesystem event delivery
      # (FSEvents/inotify); build sandboxes without it (nixbuild's darwin
      # builders) cannot run it. Vibe consumes watchfiles as a library.
      watchfiles = pyprev.watchfiles.overridePythonAttrs (_: {
        doCheck = false;
      });

      # mcp's test inputs pull every optional extra into the build closure,
      # and vibe consumes it purely as a runtime library.
      mcp = pyprev.mcp.overridePythonAttrs (_: {
        doCheck = false;
      });

      # sse-starlette's test inputs drag in fastapi and, transitively,
      # scipy -- which needs big-parallel builders that nixbuild's darwin
      # fleet does not offer. Vibe only consumes sse-starlette at runtime.
      # nixpkgs lists starlette only under the "examples" extra while the
      # built wheel requires it, so keep it as a real runtime dep.
      sse-starlette = pyprev.sse-starlette.overridePythonAttrs (old: {
        doCheck = false;
        dependencies = (old.dependencies or [ ]) ++ [ pyprev.starlette ];
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

  # Closed-source binary runtime (cp312-abi3 wheels) that backs Vibe's unified
  # harness session backend. Upstream pins the exact version; it used to be
  # optional at runtime, but since 2.25.5 vibe imports it unconditionally on
  # the interactive startup path (vibe.app_server._provided_tools, issue
  # #9563), so it must ship in the closure.
  harnessWheels = {
    x86_64-linux = {
      platform = "manylinux_2_28_x86_64";
      hash = "sha256-YB3esbdTEGGBFtP1xjBf9yDU9DF7jARwyOK8VSu/HEU=";
    };
    aarch64-linux = {
      platform = "manylinux_2_28_aarch64";
      hash = "sha256-C3Ndi70LgbXoYa6NqhsZSmRK/tPoguvEgD7QrbSFKcw=";
    };
    aarch64-darwin = {
      platform = "macosx_11_0_arm64";
      hash = "sha256-+XiH5c3zO4++nfoBjeDsyzph1HNYwHX4MsWgI48vJ/I=";
    };
  };

  mistralai-vibe-local-harness = python.pkgs.buildPythonPackage rec {
    pname = "mistralai-vibe-local-harness";
    version = "0.5.1";
    format = "wheel";

    src = fetchPypi {
      pname = "mistralai_vibe_local_harness";
      inherit version;
      format = "wheel";
      dist = "cp312";
      python = "cp312";
      abi = "abi3";
      inherit (harnessWheels.${python3.stdenv.hostPlatform.system}) platform hash;
    };

    dependencies = with python.pkgs; [
      anyio
      certifi
      httpx
      mcp
      mistralai
      opentelemetry-api
      pydantic
      rfc8785
      truststore
    ];

    pythonImportsCheck = [ "mistralai_vibe_local_harness" ];

    meta = with lib; {
      description = "Local Unified Harness runtime and native bindings for Vibe";
      homepage = "https://pypi.org/project/mistralai-vibe-local-harness/";
      license = flake.lib.licenses.unfree;
      sourceProvenance = with sourceTypes; [ binaryNativeCode ];
      platforms = builtins.attrNames harnessWheels;
    };
  };
in
python.pkgs.buildPythonApplication rec {
  pname = "mistral-vibe";
  version = "2.25.5";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "mistralai";
    repo = "mistral-vibe";
    tag = "v${version}";
    hash = "sha256-pfjKq6QDHEGyOB3oRUwZAo/MOt3k3HzOIYqdTEEPsAY=";
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
    miniaudio
    mistralai
    mistralai-vibe-local-harness
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
  # so drift fails the build. `vibe.app_server.local` covers the interactive
  # startup path, which imports mistralai_vibe_local_harness unconditionally
  # since 2.25.5 (issue #9563).
  pythonImportsCheck = [
    "vibe"
    "vibe.cli.cli"
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
    inherit mistralai-vibe-local-harness;
  };

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
