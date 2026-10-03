{
  lib,
  flake,
  python3Packages,
  fetchFromGitHub,
  fetchPypi,
  fetchurl,
  rustPlatform,
  # Set by consumers to build variants with extra python dependencies (e.g. a
  # local-ML variant adding sentence-transformers so embeddings/reranker can
  # run fully offline).
  extraPythonDeps ? [ ],
}:
let
  toktok-rs = python3Packages.buildPythonPackage rec {
    pname = "toktok-rs";
    version = "0.1.4";

    pyproject = true;

    src = fetchPypi {
      pname = "toktok_rs";
      inherit version;
      hash = "sha256-VmlGDK4Mdlxhg6ZIrrDxK7YnQ/HfRQ+QqwUeYq+DxCY=";
    };

    cargoDeps = rustPlatform.importCargoLock {
      lockFile = ./Cargo.lock;
    };

    nativeBuildInputs = with rustPlatform; [
      cargoSetupHook
      maturinBuildHook
    ];

    # Tests require network access (reference tokenizer vocab downloads)
    doCheck = false;

    pythonImportsCheck = [ "toktok" ];

    meta = with lib; {
      description = "Fast, exact BPE tokenizer for OpenAI encodings — Rust core, tiktoken-identical ids";
      homepage = "https://github.com/vectorize-io/toktok";
      license = licenses.mit;
      maintainers = with flake.lib.maintainers; [ wanderer ];
      platforms = platforms.all;
    };
  };

  github-copilot-sdk = python3Packages.buildPythonPackage rec {
    pname = "github-copilot-sdk";
    version = "1.0.13";

    # Installing a prebuilt wheel, not building from source
    format = "wheel";

    # PyPI ships wheel only (no sdist); the source repo injects the version
    # at publish time (pyproject.toml carries a 0.0.0.dev0 sentinel), so the
    # wheel is the canonical release artifact. fetchPypi can't express it:
    # the project directory is dashed while the wheel filename uses
    # underscores.
    src = fetchurl {
      url = "https://files.pythonhosted.org/packages/2d/6d/4f2e3dddc576ff49739317adba6f9b8c35e93b835ece923e46f1b7fa6028/github_copilot_sdk-${version}-py3-none-any.whl";
      hash = "sha256-lB3VtVzzK6Vcc8ZRBSpKUrJZtHDGi/amrD0kDCNUAsk=";
    };

    dependencies = with python3Packages; [
      python-dateutil
      pydantic
      httpx
    ];

    # No tests ship in the wheel; upstream tests require a Copilot CLI session
    doCheck = false;

    pythonImportsCheck = [ "copilot" ];

    meta = with lib; {
      description = "Python SDK for GitHub Copilot CLI";
      homepage = "https://github.com/github/copilot-sdk";
      license = licenses.mit;
      maintainers = with flake.lib.maintainers; [ wanderer ];
      platforms = platforms.all;
    };
  };
in
python3Packages.buildPythonApplication rec {
  pname = "hindsight";
  version = "0.10.1";

  src = fetchFromGitHub {
    owner = "vectorize-io";
    repo = "hindsight";
    tag = "v${version}";
    hash = "sha256-/qafCyuk4Vrum19AoNRtbTo+eBGP90XzNdH/LBHO4Ig=";
  };

  sourceRoot = "${src.name}/hindsight-api-slim";

  pyproject = true;

  build-system = [ python3Packages.hatchling ];

  dependencies =
    with python3Packages;
    [
      asyncpg
      python-dotenv
      openai
      pydantic
      rich
      fastapi
      uvicorn
      wsproto
      sqlalchemy
      alembic
      pgvector
      greenlet
      psycopg2
      toktok-rs
      httpx
      pyjwt
      fastmcp
      python-dateutil
      opentelemetry-api
      opentelemetry-sdk
      opentelemetry-instrumentation-fastapi
      opentelemetry-exporter-prometheus
      opentelemetry-exporter-otlp-proto-http
      opentelemetry-semantic-conventions
      dateparser
      regex
      google-genai
      google-auth
      anthropic
      typer
      cohere
      litellm
      markitdown
      obstore
      uvloop
      pyasn1
      urllib3
      protobuf
      pillow
      cryptography
      filelock
      authlib
      orjson
      python-multipart
      aiohttp
      pygments
      boto3
      json-repair
      claude-agent-sdk
      github-copilot-sdk
      croniter
      numpy
    ]
    ++ extraPythonDeps;

  nativeBuildInputs = [ python3Packages.pythonRelaxDepsHook ];
  pythonRelaxDeps = true;

  postPatch = ''
    substituteInPlace pyproject.toml \
      --replace-fail 'psycopg2-binary' 'psycopg2'
  '';

  # Disable runtime deps check because nixpkgs package names (e.g. psycopg2)
  # don't always match PyPI distribution names (e.g. psycopg2-binary).
  # All required packages are explicitly listed in dependencies.
  dontCheckRuntimeDeps = true;

  # Tests require network access and testcontainers
  doCheck = false;

  passthru.category = "AI Assistants";

  meta = with lib; {
    description = "Hindsight: Agent Memory That Works Like Human Memory";
    homepage = "https://github.com/vectorize-io/hindsight";
    changelog = "https://github.com/vectorize-io/hindsight/releases/tag/v${version}";
    license = licenses.mit;
    sourceProvenance = with sourceTypes; [ fromSource ];
    maintainers = with flake.lib.maintainers; [ wanderer ];
    mainProgram = "hindsight-api";
    platforms = platforms.all;
  };
}
