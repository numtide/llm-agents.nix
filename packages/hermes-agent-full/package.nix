{
  lib,
  stdenv,
  flake,
  python3,
  fetchFromGitHub,
  fetchPypi,
  versionCheckHook,
  versionCheckHomeHook,
  buildNpmPackage,
  nodejs,
  ripgrep,
  git,
  openssh,
  ffmpeg,
  agent-browser,
  playwright-driver,
}:
let
  pname = "hermes-agent-full";
  upstreamVersion = "0.11.0";
  snapshotDate = "2026-04-25";
  version = "${upstreamVersion}-unstable-${snapshotDate}";
  rev = "47420a84b9dce2a09e6a71600954c11e148c3242";

  deps = import ./deps.nix {
    inherit lib python3 fetchPypi;
  };

  inherit (deps)
    daytona
    honcho-ai
    dingtalk-stream
    alibabacloud-dingtalk
    lark-oapi
    ;

  pyPkgs = python3.pkgs;

  src = fetchFromGitHub {
    owner = "NousResearch";
    repo = "hermes-agent";
    inherit rev;
    hash = "sha256-qjWX9XxBYs41Pq6Tb7UNqepuS4XTxLdaNToVquKJKe0=";
  };

  webSrc = builtins.path {
    name = "${pname}-web-source";
    path = src + "/web";
  };

  whatsappBridgeSrc = builtins.path {
    name = "${pname}-whatsapp-bridge-source";
    path = src + "/scripts/whatsapp-bridge";
  };

  exa-py = pyPkgs.buildPythonPackage rec {
    pname = "exa-py";
    version = "2.10.2";
    pyproject = true;

    src = fetchPypi {
      pname = "exa_py";
      inherit version;
      hash = "sha256-94HzCxmfEQIzM4RyitrmS7Faa7yr+pfpH9cF+QrP/EU=";
    };

    build-system = with pyPkgs; [
      poetry-core
    ];

    dependencies = with pyPkgs; [
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

  fal-client = pyPkgs.buildPythonPackage rec {
    pname = "fal-client";
    version = "0.13.1";
    pyproject = true;

    src = fetchPypi {
      pname = "fal_client";
      inherit version;
      hash = "sha256-nhwH0KYbRSqP+0jBmd5fJUPXVG8SMPYxI3BEMSfF6Tc=";
    };

    build-system = with pyPkgs; [
      setuptools
      setuptools-scm
    ];

    dependencies = with pyPkgs; [
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

  parallel-web = pyPkgs.buildPythonPackage rec {
    pname = "parallel-web";
    version = "0.4.2";
    pyproject = true;

    src = fetchPypi {
      pname = "parallel_web";
      inherit version;
      hash = "sha256-WZtajzh9w1x9yMgeNy6t9pWKQKys6li/Fw38ZjwAPac=";
    };

    build-system = with pyPkgs; [
      hatchling
      hatch-fancy-pypi-readme
    ];

    pypaBuildFlags = [ "--skip-dependency-check" ];

    dependencies = with pyPkgs; [
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

  frontend = buildNpmPackage {
    pname = "${pname}-web";
    src = webSrc;
    inherit version;
    npmDepsHash = "sha256-4Z8KQ69QhO83X6zff+5urWBv6MME686MhTTMdwSl65o=";

    postPatch = ''
      substituteInPlace vite.config.ts \
        --replace-fail 'outDir: "../hermes_cli/web_dist",' 'outDir: "dist",'
    '';

    installPhase = ''
      runHook preInstall
      cp -r dist $out
      runHook postInstall
    '';
  };

  rootNodeModules = buildNpmPackage {
    pname = "${pname}-node-modules";
    inherit src version;
    sourceRoot = src.name;
    npmDepsHash = "sha256-KiXucB+kz9wnS2ds+MJl4jlSAnpQXZrIgeM895BP4+4=";
    dontNpmBuild = true;

    installPhase = ''
      runHook preInstall
      mkdir -p $out
      cp -r node_modules package.json package-lock.json $out/
      runHook postInstall
    '';
  };

  whatsappBridge = buildNpmPackage (_finalAttrs: {
    pname = "${pname}-whatsapp-bridge";
    src = whatsappBridgeSrc;
    inherit version;

    npmDepsFetcherVersion = 2;
    npmDepsHash = "sha256-IVlhR3s64o10nYy1N/qqHPM3j9QVz7WeQwe6sCYJM9c=";
    forceGitDeps = true;
    makeCacheWritable = true;
    dontNpmBuild = true;

    installPhase = ''
      runHook preInstall
      mkdir -p $out
      cp -r allowlist.js bridge.js node_modules package.json $out/
      if [ -e package-lock.json ]; then
        cp package-lock.json $out/
      fi
      runHook postInstall
    '';
  });
in
pyPkgs.buildPythonApplication {
  inherit pname version src;
  pyproject = true;

  build-system = with pyPkgs; [
    setuptools
  ];

  dependencies =
    with pyPkgs;
    [
      openai
      anthropic
      python-dotenv
      fire
      httpx
      socksio
      rich
      tenacity
      pyyaml
      requests
      jinja2
      pydantic
      prompt-toolkit
      exa-py
      firecrawl-py
      parallel-web
      fal-client
      modal
      daytona
      debugpy
      pytest
      pytest-asyncio
      pytest-xdist
      ty
      ruff
      qrcode
      python-telegram-bot
      discordpy
      aiohttp
      slack-bolt
      slack-sdk
      croniter
      simple-term-menu
      edge-tts
      elevenlabs
      faster-whisper
      sounddevice
      numpy
      ptyprocess
      honcho-ai
      mcp
      agent-client-protocol
      mistralai
      boto3
      dingtalk-stream
      alibabacloud-dingtalk
      lark-oapi
      google-api-python-client
      google-auth-oauthlib
      google-auth-httplib2
      fastapi
      uvicorn
      pyjwt
      cryptography
      pynacl
    ]
    ++ lib.optionals stdenv.hostPlatform.isLinux [
      mautrix
      markdown
      aiosqlite
      asyncpg
    ];

  pythonRelaxDeps = [
    "tenacity"
    "requests"
    "pydantic"
    "firecrawl-py"
    "pyjwt"
    "python-telegram-bot"
    "mautrix"
  ];

  preBuild = ''
    mkdir -p hermes_cli
    cp -r ${frontend}/. hermes_cli/web_dist
  '';

  postInstall = ''
    site_packages="$out/${python3.sitePackages}"

    cp -r ${rootNodeModules}/node_modules "$site_packages/"
    cp ${rootNodeModules}/package.json ${rootNodeModules}/package-lock.json "$site_packages/"

    mkdir -p "$site_packages/scripts/whatsapp-bridge"
    cp -r ${whatsappBridge}/. "$site_packages/scripts/whatsapp-bridge/"
  '';

  makeWrapperArgs = [
    "--prefix"
    "PATH"
    ":"
    (lib.makeBinPath [
      nodejs
      ripgrep
      git
      openssh
      ffmpeg
      agent-browser
    ])
    "--set"
    "PLAYWRIGHT_BROWSERS_PATH"
    "${playwright-driver.browsers}"
    "--set"
    "PLAYWRIGHT_SKIP_VALIDATE_HOST_REQUIREMENTS"
    "true"
  ];

  pythonImportsCheck = [
    "hermes_cli"
    "slack_bolt"
    "discord"
    "telegram.ext"
    "croniter"
    "daytona"
    "honcho"
    "dingtalk_stream"
    "alibabacloud_dingtalk"
    "lark_oapi"
    "googleapiclient"
  ];

  doInstallCheck = true;
  nativeInstallCheckInputs = [
    versionCheckHook
    versionCheckHomeHook
  ];
  versionCheckProgramArg = [ "--version" ];
  preVersionCheck = ''
    version=${upstreamVersion}
  '';

  passthru.category = "AI Assistants";

  meta = with lib; {
    description = "Self-improving AI agent by Nous Research with full packaged integrations and dashboard assets";
    homepage = "https://hermes-agent.nousresearch.com/";
    changelog = "https://github.com/NousResearch/hermes-agent/commit/${rev}";
    license = licenses.mit;
    sourceProvenance = with sourceTypes; [ fromSource ];
    maintainers = with flake.lib.maintainers; [ aliez-ren ];
    mainProgram = "hermes";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
      "aarch64-darwin"
    ];
  };
}
