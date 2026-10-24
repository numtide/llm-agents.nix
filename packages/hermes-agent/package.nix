{
  lib,
  stdenv,
  flake,
  python3,
  rustPlatform,
  fetchFromGitHub,
  fetchPypi,
  buildNpmPackage,
  nodejs,
  olm,
  versionCheckHook,
  writeText,
  versionCheckHomeHook,
}:

let
  # Hermes' Anthropic adapter passes httpx objects; SDK 1.x requires httpx2.
  # Keep this private dependency aligned with the upstream extra, not nixpkgs.
  anthropic = python3.pkgs.anthropic.overridePythonAttrs (old: {
    version = "0.87.0";
    src = fetchFromGitHub {
      owner = "anthropics";
      repo = "anthropic-sdk-python";
      tag = "v0.87.0";
      hash = "sha256-T9DMOwtCd63BNR3V21Y2s1BbUg5X4N5W/RjtmG8+aWs=";
    };
    dependencies =
      builtins.filter (dependency: dependency.pname or "" != "httpx2") old.dependencies
      ++ [
        python3.pkgs.httpx
        python3.pkgs.distro
      ];
  });

  # Native (PyO3) runtime for hermes' Relay lifecycle and shared metrics.
  # PyPI ships wheels only, so build from source with maturin.
  # Version is kept in range of hermes' pyproject constraint by update.py.
  nemo-relay = python3.pkgs.buildPythonPackage rec {
    pname = "nemo-relay";
    version = "0.10.4";
    pyproject = true;

    src = fetchFromGitHub {
      owner = "NVIDIA";
      repo = "NeMo-Relay";
      tag = version;
      hash = "sha256-6wB3TnrkymwsTia5RVq7fQ6g375lZHba0DUXTFjxV2w=";
    };

    cargoDeps = rustPlatform.fetchCargoVendor {
      inherit src;
      name = "nemo-relay-${version}";
      hash = "sha256-P9+/lvxQVm+H1+qM8lPo2aXMLJTHM1F8HWS7x0I2jPs=";
    };

    nativeBuildInputs =
      with rustPlatform;
      [
        cargoSetupHook
        maturinBuildHook
      ]
      # Tags lag the workspace Cargo.toml version that pyproject derives from.
      ++ [ python3.pkgs.pyprojectVersionPatchHook ];

    pythonImportsCheck = [
      "nemo_relay"
      "nemo_relay._native"
    ];

    meta = with lib; {
      description = "Python bindings for the NeMo Relay agent runtime";
      homepage = "https://github.com/NVIDIA/NeMo-Relay";
      license = licenses.asl20;
      sourceProvenance = with sourceTypes; [ fromSource ];
      platforms = platforms.unix;
    };
  };

  # Native (PyO3) document-to-markdown converter; PyPI ships wheels only.
  firecrawl-anydoc = python3.pkgs.buildPythonPackage rec {
    pname = "firecrawl-anydoc";
    version = "0.2.4";
    pyproject = true;

    src = fetchFromGitHub {
      owner = "firecrawl";
      repo = "anydoc";
      tag = "v${version}";
      hash = "sha256-rGv3Bh+zmF9xFUgf8RaSmfyB/gfuQ13iC389i6VZIlM=";
    };

    cargoDeps = rustPlatform.fetchCargoVendor {
      inherit src;
      name = "anydoc-${version}";
      hash = "sha256-yhW5HSzVrZCms4x36J2NGIn1e5YLIgjuNKXM9EJ9J8c=";
    };

    buildAndTestSubdir = "python";

    nativeBuildInputs = with rustPlatform; [
      cargoSetupHook
      maturinBuildHook
    ];

    pythonImportsCheck = [
      "anydoc"
      "anydoc._anydoc"
    ];

    meta = with lib; {
      description = "Convert documents to GitHub-Flavored Markdown";
      homepage = "https://github.com/firecrawl/anydoc";
      license = licenses.mit;
      sourceProvenance = with sourceTypes; [ fromSource ];
      platforms = platforms.unix;
    };
  };

  cdp-use = python3.pkgs.buildPythonPackage rec {
    pname = "cdp-use";
    version = "1.4.5";
    pyproject = true;

    src = fetchPypi {
      pname = "cdp_use";
      inherit version;
      hash = "sha256-DaOjLfRjNqA/9aIrxrxELNfS8tUKEY/UhW8p039tJqA=";
    };

    build-system = [ python3.pkgs.hatchling ];

    dependencies = with python3.pkgs; [
      httpx
      typing-extensions
      websockets
    ];

    pythonImportsCheck = [ "cdp_use" ];

    meta = with lib; {
      description = "Type-safe Python client for the Chrome DevTools Protocol";
      homepage = "https://github.com/browser-use/cdp-use";
      license = licenses.mit;
      sourceProvenance = with sourceTypes; [ fromSource ];
      platforms = platforms.all;
    };
  };

  fetch-use = python3.pkgs.buildPythonPackage rec {
    pname = "fetch-use";
    version = "0.4.0";
    pyproject = true;

    src = fetchPypi {
      pname = "fetch_use";
      inherit version;
      hash = "sha256-lRGYfUkH7G2sUB4h1mlG0QCY9mtdIbwqukGJzYG6GJo=";
    };

    build-system = [ python3.pkgs.hatchling ];

    pythonImportsCheck = [ "fetch_use" ];

    meta = with lib; {
      description = "Python client for the Browser Use fetch API";
      homepage = "https://github.com/browser-use/fetch-use";
      license = licenses.mit;
      sourceProvenance = with sourceTypes; [ fromSource ];
      platforms = platforms.all;
    };
  };

  browser-harness = python3.pkgs.buildPythonPackage rec {
    pname = "browser-harness";
    version = "0.1.13";
    pyproject = true;

    src = fetchPypi {
      pname = "browser_harness";
      inherit version;
      hash = "sha256-KE3FR6BCwwn+r9mp9KdLKoZRt5Y+o6xssvLWSIn2qPM=";
    };

    build-system = [ python3.pkgs.setuptools ];

    # Upstream pins setuptools==84.0.0 in build-system.requires.
    pypaBuildFlags = [ "--skip-dependency-check" ];

    dependencies = [
      cdp-use
      fetch-use
      python3.pkgs.pillow
      python3.pkgs.websockets
    ];

    pythonRelaxDeps = [
      "pillow"
      "websockets"
    ];

    pythonImportsCheck = [ "browser_harness" ];

    meta = with lib; {
      description = "Harness that lets agents drive a browser over CDP";
      homepage = "https://github.com/browser-use/browser-harness";
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

  version = "0.22.5";
  # The commit of the tag. Hermes ignores an install stamp without one.
  rev = "bf0203a794a07aac3ff764972ab9087baa4e4f4e";

  src = fetchFromGitHub {
    owner = "NousResearch";
    repo = "hermes-agent";
    tag = "v${version}";
    hash = "sha256-/sgbU4D8wSQ0GmfR8Qwpn4YySh+ELQ6SnplCdGt6pnQ=";
    # contributors/emails/ holds paths differing only in case; they collapse
    # on case-insensitive stores (APFS) so the NAR hash diverges between
    # Linux and darwin. Unused at build/runtime. Upstream:
    # NousResearch/hermes-agent#88257
    postFetch = ''
      rm -rf "$out/contributors"
    '';
  };

  # Upstream moved ui-tui/ and web/ into npm workspaces with a single root
  # package-lock.json, so both frontends must be built from the repo root.
  # `hermes --tui` runs the compiled Ink/React bundle via HERMES_TUI_DIR
  # (hermes_cli/main.py:_make_tui_argv fast-path, #4364) and
  # `hermes dashboard` serves the Vite app via HERMES_WEB_DIST.
  hermes-frontend = buildNpmPackage {
    pname = "hermes-frontend";
    inherit version src;
    npmDepsHash = "sha256-4rf/ivClNHrUUJSMAHStx+fPnFc5EUfDuvefCt5Ry74=";

    # The apps/desktop workspace pulls in electron; skip its binary download
    # and all install scripts — the esbuild/vite builds below don't need them.
    # Upstream's .npmrc sets engine-strict=true and package.json rejects the
    # npm range shipped with nixpkgs' nodejs to work around a min-release-age
    # bug, which is irrelevant for the offline install here.
    npmFlags = [
      "--ignore-scripts"
      "--engine-strict=false"
    ];
    env.ELECTRON_SKIP_BINARY_DOWNLOAD = "1";

    buildPhase = ''
      runHook preBuild
      npm run build --workspace ui-tui
      node scripts/build/web.mjs --source "$PWD" --icons "$PWD" --out "$TMPDIR/web-dist"
      runHook postBuild
    '';

    # dist/entry.js is a self-contained esbuild bundle; package.json is kept
    # so node resolves it as an ES module.
    installPhase = ''
      runHook preInstall
      mkdir -p $out/lib/hermes-tui $out/share/hermes-web
      cp -r ui-tui/dist ui-tui/package.json $out/lib/hermes-tui/
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
      snowballstemmer
      python-dotenv
      fire
      httpx
      rich
      tenacity
      pathspec
      pillow
      ruamel-yaml
      tomli-w
      truststore
      requests
      jinja2
      pydantic
      firecrawl-anydoc
      # Interactive CLI
      prompt-toolkit
      # Cron scheduler
      croniter
      # Process / PID management
      psutil
      # MCP
      mcp
      # Tools
      exa-py
      firecrawl-py
      parallel-web
      fal-client
      browser-harness
      # Text-to-speech
      edge-tts
      # Skills Hub
      pyjwt
      cryptography
      # Relay lifecycle + shared metrics
      nemo-relay
    ]
    # faster-whisper -> av SIGKILLs during import on darwin; voice is optional.
    ++ lib.optionals stdenv.hostPlatform.isLinux [ faster-whisper ]
    ++ optionalDeps.gateway
    ++ optionalDeps.misc;

  # Upstream extras only warn-and-disable at runtime when missing (#4175), so
  # ship every extra nixpkgs has. Not yet packaged: honcho, daytona, dingtalk,
  # feishu.
  # libolm is marked insecure in nixpkgs but mautrix[encryption] needs it for
  # Matrix E2EE.
  clearedOlm = olm.overrideAttrs (old: {
    meta = old.meta // {
      knownVulnerabilities = [ ];
    };
  });

  # pyramid dropped its pkg_resources shim on python 3.14, so slack-bolt's
  # pyramid adapter tests fail at collection with ModuleNotFoundError.
  # The async assistant scenario tests wait on real timers and time out on
  # loaded builders.
  # pkg-resources-backport tests need jaraco-path, broken on darwin
  slack-bolt' =
    (python3.pkgs.slack-bolt.override {
      pkg-resources-backport = python3.pkgs.pkg-resources-backport.overridePythonAttrs {
        doCheck = !stdenv.hostPlatform.isDarwin;
      };
    }).overridePythonAttrs
      (old: {
        disabledTestPaths = (old.disabledTestPaths or [ ]) ++ [
          "tests/adapter_tests/pyramid/"
          "tests/scenario_tests_async/test_events_assistant.py"
        ];
      });

  # Upstream pins agent-client-protocol==0.9.0; nixpkgs' 0.11.x regenerated the
  # ACP schema and dropped ModelInfo/SetSessionModelResponse/SessionModelState,
  # which acp_adapter still imports, so hermes-acp fails at startup (#7650).
  agent-client-protocol' = python3.pkgs.agent-client-protocol.overridePythonAttrs (old: {
    version = "0.9.0";
    src = old.src.override {
      tag = "0.9.0";
      hash = "sha256-8Xf2S85yNsP/HhpCw9UqdoDdeDHdggvYcnvJbilAVuU=";
    };
    # 0.9.0 predates the tests/http suite that nixpkgs' expression disables.
    disabledTestPaths = [ ];
    disabledTests = (old.disabledTests or [ ]) ++ [
      # subprocess spawn exceeds the 2s timeout in the sandbox
      "test_run_agent_stdio_buffer_limit"
    ];
  });

  optionalDeps = with python3.pkgs; {
    gateway = [
      # [messaging] / [slack]
      slack-bolt'
      slack-sdk
      python-telegram-bot
      discordpy
      aiohttp
      # [cron]
      croniter
      # [web]
      fastapi
      httptools
      uvicorn
      # [markdown] — used by matrix and other formatters
      markdown
    ]
    ++ lib.optionals stdenv.hostPlatform.isLinux [
      # [matrix] — nixpkgs mautrix lacks the encryption extra, so add its
      # crypto deps explicitly.
      mautrix
      (python-olm.override { olm = clearedOlm; })
      unpaddedbase64
      pycryptodome
      base58
      aiosqlite
      asyncpg
      aiohttp-socks
    ];
    misc = [
      # [cli]
      simple-term-menu
      # [pty]
      ptyprocess
      # [acp]
      agent-client-protocol'
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
      # web_search backend hermes would otherwise try to pip-install (#8259)
      ddgs
    ];
  };

  # The TUI spawns `$HERMES_PYTHON -m tui_gateway.entry`; sys.executable is the
  # bare interpreter, so give it an env with the runtime deps. The dashboard
  # PTY path copies wrapper env into a nested Node subprocess, which then
  # resolves the gateway import root from HERMES_PYTHON_SRC_ROOT.
  pythonEnv = python3.withPackages (_: hermesDeps);

  installStamp = writeText "install-stamp.json" (
    builtins.toJSON {
      schemaVersion = 2;
      commit = rev;
      baseVersion = version;
      displayVersion = version;
      distance = 0;
      dirty = false;
      source = "nix";
      distribution = "nix";
      updateMechanism = "external";
      # Desktop: use an external Hermes instead of a bundled one.
      payload = "bootstrap";
    }
  );
in
python3.pkgs.buildPythonApplication {
  pname = "hermes-agent";
  inherit version src;
  pyproject = true;

  build-system = with python3.pkgs; [
    setuptools
  ];

  # These re-exec sys.executable, which is the bare interpreter without Hermes'
  # dependencies under Nix. Use the wrapper-provided env.
  postPatch = ''
    # Fail an update rather than silently keeping an SDK that upstream replaced.
    ${python3.interpreter} -c 'import tomllib; p = tomllib.load(open("pyproject.toml", "rb")); expected = "anthropic==${anthropic.version}"; actual = p["project"]["optional-dependencies"]["anthropic"]; assert actual == [expected], f"Anthropic pin changed: {actual}; review the private SDK override"'
    substituteInPlace tui_gateway/server.py \
      --replace-fail 'argv = [sys.executable, "-m", "tui_gateway.slash_worker"' \
        'argv = [os.environ.get("HERMES_PYTHON", sys.executable), "-m", "tui_gateway.slash_worker"'
    substituteInPlace tools/browser_use_cli.py \
      --replace-fail 'return [sys.executable, "-m", "browser_harness.run"]' \
        'return [os.environ.get("HERMES_PYTHON", sys.executable), "-m", "browser_harness.run"]'
    substituteInPlace hermes_cli/doctor_platform.py \
      --replace-fail '[sys.executable, "-c", "import hermes_cli.web_server"]' \
        '[os.environ.get("HERMES_PYTHON", sys.executable), "-c", "import hermes_cli.web_server"]'
    substituteInPlace hermes_cli/gateway_runtime_start.py \
      --replace-fail 'command = [sys.executable, "-m", "hermes_cli.main"' \
        'command = [os.environ.get("HERMES_PYTHON", sys.executable), "-m", "hermes_cli.main"'
  '';

  # setup.py refuses to build wheels/sdists unless it knows this is a Nix
  # (uv2nix-style) build; upstream gates it behind this env var.
  env.HERMES_NIX_BUILD = "1";

  dependencies = hermesDeps;
  optional-dependencies = optionalDeps;

  makeWrapperArgs = [
    "--set"
    "HERMES_TUI_DIR"
    "${hermes-frontend}/lib/hermes-tui"
    "--set"
    "HERMES_WEB_DIST"
    "${hermes-frontend}/share/hermes-web"
    "--set"
    "HERMES_PYTHON"
    "${pythonEnv}/bin/python3"
    "--set"
    "HERMES_PYTHON_SRC_ROOT"
    "${placeholder "out"}/${python3.sitePackages}"
    "--set"
    "HERMES_NODE"
    "${nodejs}/bin/node"
    # Runtime data is copied to $out/share/hermes in postInstall; point Hermes at it.
    "--set"
    "HERMES_BUNDLED_SKILLS"
    "${placeholder "out"}/share/hermes/skills"
    "--set"
    "HERMES_OPTIONAL_SKILLS"
    "${placeholder "out"}/share/hermes/optional-skills"
    "--set"
    "HERMES_BUNDLED_PLUGINS"
    "${placeholder "out"}/share/hermes/plugins"
    "--set"
    "HERMES_BUNDLED_LOCALES"
    "${placeholder "out"}/share/hermes/locales"
    # Disable runtime pip installs; absent extras disable cleanly.
    "--set"
    "HERMES_DISABLE_LAZY_INSTALLS"
    "1"
    # node+npm on PATH short-circuits _ensure_tui_node()'s download bootstrap.
    "--prefix"
    "PATH"
    ":"
    "${nodejs}/bin"
  ];

  # Upstream keeps runtime data outside site-packages and locates it through
  # wrapper environment variables. Preserve that layout because setuptools
  # intentionally omits plugin manifests from the wheel since 2026.8.3.
  postInstall = ''
    mkdir -p $out/share/hermes
    cp -r ${src}/skills $out/share/hermes/skills
    cp -r ${src}/optional-skills $out/share/hermes/optional-skills
    cp -r ${src}/plugins $out/share/hermes/plugins
    cp -r ${src}/locales $out/share/hermes/locales
    # The sources only carry a 0.0.0 placeholder version.
    cp ${installStamp} $out/${python3.sitePackages}/install-stamp.json
  '';

  pythonRelaxDeps = [
    "openai"
    "python-dotenv"
    "tenacity"
    "ruamel.yaml"
    "requests"
    "pydantic"
    "pathspec"
    "firecrawl-py"
    "pyjwt"
    "cryptography"
    "certifi"
    "packaging"
    "urllib3"
    "websockets"
    # nixpkgs moved past upstream's == pins
    "prompt_toolkit"
    "markdown"
    "rich"
    "pillow"
    "croniter"
    "exa-py"
  ];

  # Only used by upstream's icon generator, which is not installed.
  pythonRemoveDeps = [ "resvg-py" ];

  pythonImportsCheck = [
    "hermes_cli"
    "hermes_cli.dashboard_auth"
    "hermes_cli.proxy"
    # #7650: acp_adapter needs the pre-0.11 ACP schema; assert it imports.
    "acp_adapter.server"
    # #4175: adapters swallow ImportError, so assert these import.
    "slack_bolt"
    "discord"
    "telegram.ext"
    "croniter"
    # relay_runtime imports this lazily and silently degrades to a noop
    # runtime when missing, so assert it imports.
    "nemo_relay"
    "browser_harness"
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
    grep -q HERMES_PYTHON_SRC_ROOT $out/bin/hermes
    grep -q HERMES_BUNDLED_SKILLS $out/bin/hermes
    grep -q HERMES_OPTIONAL_SKILLS $out/bin/hermes
    grep -q HERMES_BUNDLED_PLUGINS $out/bin/hermes
    grep -q HERMES_BUNDLED_LOCALES $out/bin/hermes
    test -f $out/share/hermes/locales/en.yaml
    test -f ${hermes-frontend}/lib/hermes-tui/dist/entry.js
    test -f ${hermes-frontend}/share/hermes-web/index.html
    test -d $out/share/hermes/skills
    test -d $out/share/hermes/optional-skills
    test -n "$(find $out/share/hermes/plugins -name plugin.yaml -print -quit)"
    ${pythonEnv}/bin/python3 -c 'import dotenv, tenacity, openai'
    # Slash workers run HERMES_PYTHON with PYTHONPATH=HERMES_PYTHON_SRC_ROOT.
    PYTHONPATH="$out/${python3.sitePackages}" \
      ${pythonEnv}/bin/python3 -c 'import tui_gateway.slash_worker, ruamel.yaml'
    # #7725: DaemonThreadPoolExecutor mirrors CPython ThreadPoolExecutor
    # internals; assert submit() actually executes work on this Python.
    PYTHONPATH="$out/${python3.sitePackages}" \
      ${pythonEnv}/bin/python3 -c 'from tools.daemon_pool import DaemonThreadPoolExecutor; assert DaemonThreadPoolExecutor(max_workers=1).submit(lambda: 42).result(timeout=30) == 42'
  ''
  + lib.optionalString stdenv.hostPlatform.isLinux ''
    # Matrix E2EE: mautrix.crypto must import and the disable switch wired in.
    ${pythonEnv}/bin/python3 -c 'import mautrix.crypto, asyncpg, aiosqlite'
    grep -q HERMES_DISABLE_LAZY_INSTALLS $out/bin/hermes
  '';

  passthru = {
    category = "AI Assistants";
    inherit hermes-frontend nemo-relay installStamp;
  };

  meta = with lib; {
    description = "Self-improving AI agent by Nous Research — creates skills from experience and runs anywhere";
    homepage = "https://hermes-agent.nousresearch.com/";
    changelog = "https://github.com/NousResearch/hermes-agent/releases/tag/v${version}";
    license = licenses.mit;
    sourceProvenance = with sourceTypes; [ fromSource ];
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
      "aarch64-darwin"
    ];
    maintainers = with flake.lib.maintainers; [
      aliez-ren
      mulatta
    ];
    mainProgram = "hermes";
  };
}
