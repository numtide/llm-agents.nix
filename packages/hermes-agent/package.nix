{
  lib,
  stdenv,
  flake,
  python3,
  fetchFromGitHub,
  fetchPypi,
  buildNpmPackage,
  nodejs,
  versionCheckHook,
  versionCheckHomeHook,
}:

let
  exa-py = python3.pkgs.buildPythonPackage rec {
    pname = "exa-py";
    version = "2.10.2";
    pyproject = true;

    src = fetchPypi {
      pname = "exa_py";
      inherit version;
      hash = "sha256-94HzCxmfEQIzM4RyitrmS7Faa7yr+pfpH9cF+QrP/EU=";
    };

    build-system = with python3.pkgs; [
      poetry-core
    ];

    dependencies = with python3.pkgs; [
      httpcore
      httpx
      openai
      pydantic
      python-dotenv
      requests
      typing-extensions
    ];

    pythonImportsCheck = [ "exa_py" ];

    meta = with lib; {
      description = "Python SDK for Exa API";
      homepage = "https://github.com/exa-labs/exa-py";
      license = licenses.mit;
      sourceProvenance = with sourceTypes; [ fromSource ];
      platforms = platforms.all;
    };
  };

  fal-client = python3.pkgs.buildPythonPackage rec {
    pname = "fal-client";
    version = "0.13.1";
    pyproject = true;

    src = fetchPypi {
      pname = "fal_client";
      inherit version;
      hash = "sha256-nhwH0KYbRSqP+0jBmd5fJUPXVG8SMPYxI3BEMSfF6Tc=";
    };

    build-system = with python3.pkgs; [
      setuptools
      setuptools-scm
    ];

    dependencies = with python3.pkgs; [
      httpx
      httpx-sse
      msgpack
      websockets
    ];

    pythonImportsCheck = [ "fal_client" ];

    meta = with lib; {
      description = "Python client for fal.ai";
      homepage = "https://github.com/fal-ai/fal";
      license = licenses.asl20;
      sourceProvenance = with sourceTypes; [ fromSource ];
      platforms = platforms.all;
    };
  };

  parallel-web = python3.pkgs.buildPythonPackage rec {
    pname = "parallel-web";
    version = "0.4.2";
    pyproject = true;

    src = fetchPypi {
      pname = "parallel_web";
      inherit version;
      hash = "sha256-WZtajzh9w1x9yMgeNy6t9pWKQKys6li/Fw38ZjwAPac=";
    };

    build-system = with python3.pkgs; [
      hatchling
      hatch-fancy-pypi-readme
    ];

    # Upstream pins hatchling==1.26.3 in build-system.requires; pythonRelaxDeps
    # only touches runtime metadata, so skip the build-time pin check.
    pypaBuildFlags = [ "--skip-dependency-check" ];

    dependencies = with python3.pkgs; [
      anyio
      distro
      httpx
      pydantic
      sniffio
      typing-extensions
    ];

    pythonImportsCheck = [ "parallel" ];

    meta = with lib; {
      description = "Python SDK for Parallel Web API";
      homepage = "https://github.com/parallel-web/parallel-sdk-python";
      license = licenses.asl20;
      sourceProvenance = with sourceTypes; [ fromSource ];
      platforms = platforms.all;
    };
  };

  version = "2026.5.16";

  src = fetchFromGitHub {
    owner = "NousResearch";
    repo = "hermes-agent";
    rev = "v${version}";
    hash = "sha256-d9qhrTy45Q5UsmjapqMHOVi9e+gR9zE8Nq9Z0wObLmc=";
  };

  # `hermes --tui` runs a compiled Ink/React app from ui-tui/ that the wheel
  # does not ship. Prebuild it and expose via HERMES_TUI_DIR so the CLI takes
  # the fast-path in hermes_cli/main.py:_make_tui_argv (#4364).
  hermes-tui = buildNpmPackage {
    pname = "hermes-tui";
    inherit version;
    src = "${src}/ui-tui";
    npmDepsHash = "sha256-9r1EYQ600gNXOnNXwakorpEk7hS/FPxZVbB2JksrhYs=";

    installPhase = ''
      runHook preInstall
      mkdir -p $out/lib/hermes-tui
      cp -r dist node_modules package.json $out/lib/hermes-tui/
      # @hermes/ink is a file: dep — replace dangling symlink with the source.
      rm -f $out/lib/hermes-tui/node_modules/@hermes/ink
      cp -r packages/hermes-ink $out/lib/hermes-tui/node_modules/@hermes/ink
      runHook postInstall
    '';
  };

  # `hermes dashboard` serves a Vite app from hermes_cli/web_dist. Build it
  # ahead of time and point the wrapper at the immutable output so packaged
  # installs never try to build frontend assets at runtime.
  hermes-web = buildNpmPackage {
    pname = "hermes-web";
    inherit version;
    src = "${src}/web";
    npmDepsHash = "sha256-HWB1piIPglTXbzQHXFYHLgVZIbDb60esupXSQGa1+lI=";

    buildPhase = ''
      runHook preBuild
      npm run build -- --outDir "$TMPDIR/web-dist"
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p $out/share/hermes-web
      cp -r "$TMPDIR/web-dist"/. $out/share/hermes-web/
      runHook postInstall
    '';
  };

  hermesDeps =
    with python3.pkgs;
    [
      # Core
      openai
      anthropic
      python-dotenv
      fire
      httpx
      rich
      tenacity
      pyyaml
      requests
      jinja2
      pydantic
      # Interactive CLI
      prompt-toolkit
      # MCP
      mcp
      # Tools
      exa-py
      firecrawl-py
      parallel-web
      fal-client
      # Text-to-speech
      edge-tts
      # Skills Hub
      pyjwt
    ]
    # faster-whisper -> av SIGKILLs during import on darwin; voice is optional.
    ++ lib.optionals stdenv.hostPlatform.isLinux [ faster-whisper ]
    ++ optionalDeps.gateway
    ++ optionalDeps.misc;

  # Upstream extras only warn-and-disable at runtime when missing (#4175), so
  # ship every extra nixpkgs has. Not yet packaged: honcho, daytona, dingtalk,
  # feishu.
  optionalDeps = with python3.pkgs; {
    gateway = [
      # [messaging] / [slack]
      slack-bolt
      slack-sdk
      python-telegram-bot
      discordpy
      aiohttp
      # [cron]
      croniter
      # [web]
      fastapi
      uvicorn
    ]
    ++ lib.optionals stdenv.hostPlatform.isLinux [
      # [matrix] — python-olm broken on macOS upstream.
      mautrix
      markdown
      aiosqlite
      asyncpg
    ];
    misc = [
      # [cli]
      simple-term-menu
      # [pty]
      ptyprocess
      # [acp]
      agent-client-protocol
      # [voice]
      sounddevice
      numpy
      # [tts-premium]
      elevenlabs
      # [mistral]
      mistralai
      # [bedrock]
      boto3
      # [modal]
      modal
    ];
  };

  # The TUI spawns `$HERMES_PYTHON -m tui_gateway.entry`; sys.executable is the
  # bare interpreter, so give it an env with the runtime deps. tui_gateway
  # itself is found via PYTHONPATH=$out/site-packages (HERMES_PYTHON_SRC_ROOT).
  pythonEnv = python3.withPackages (_: hermesDeps);
in
python3.pkgs.buildPythonApplication {
  pname = "hermes-agent";
  inherit version src;
  pyproject = true;

  build-system = with python3.pkgs; [
    setuptools
  ];

  dependencies = hermesDeps;
  optional-dependencies = optionalDeps;

  makeWrapperArgs = [
    "--set"
    "HERMES_TUI_DIR"
    "${hermes-tui}/lib/hermes-tui"
    "--set"
    "HERMES_WEB_DIST"
    "${hermes-web}/share/hermes-web"
    "--set"
    "HERMES_PYTHON"
    "${pythonEnv}/bin/python3"
    "--set"
    "HERMES_NODE"
    "${nodejs}/bin/node"
    # node+npm on PATH short-circuits _ensure_tui_node()'s download bootstrap.
    "--prefix"
    "PATH"
    ":"
    "${nodejs}/bin"
  ];

  pythonRelaxDeps = [
    "tenacity"
    "requests"
    "pydantic"
    "firecrawl-py"
    "pyjwt"
  ];

  pythonImportsCheck = [
    "hermes_cli"
    # #4175: adapters swallow ImportError, so assert these import.
    "slack_bolt"
    "discord"
    "telegram.ext"
    "croniter"
  ];

  doInstallCheck = true;
  nativeInstallCheckInputs = [
    versionCheckHook
    versionCheckHomeHook
  ];
  versionCheckProgramArg = [ "--version" ];

  # #4364: wrapper must wire up the TUI and a deps-capable gateway python.
  postInstallCheck = ''
    grep -q HERMES_TUI_DIR $out/bin/hermes
    grep -q HERMES_WEB_DIST $out/bin/hermes
    grep -q HERMES_PYTHON $out/bin/hermes
    test -f ${hermes-tui}/lib/hermes-tui/dist/entry.js
    test -f ${hermes-web}/share/hermes-web/index.html
    ${pythonEnv}/bin/python3 -c 'import dotenv, tenacity, openai'
  '';

  passthru = {
    category = "AI Assistants";
    inherit hermes-tui hermes-web;
  };

  meta = with lib; {
    description = "Self-improving AI agent by Nous Research — creates skills from experience and runs anywhere";
    homepage = "https://hermes-agent.nousresearch.com/";
    changelog = "https://github.com/NousResearch/hermes-agent/releases/tag/v${version}";
    license = licenses.mit;
    sourceProvenance = with sourceTypes; [ fromSource ];
    # x86_64-darwin: pyarrow (via faster-whisper chain) broken there.
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
      "aarch64-darwin"
    ];
    maintainers = with flake.lib.maintainers; [ aliez-ren ];
    mainProgram = "hermes";
  };
}
