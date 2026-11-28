{
  mkUpdater,
  lib,
  flake,
  python3,
  fetchFromGitHub,
  versionCheckHook,
  versionCheckHomeHook,
}:

let
  versionData = builtins.fromJSON (builtins.readFile ./hashes.json);
  inherit (versionData) version hash;

  parallelWebData = versionData.parallelWeb;
  sqlalchemyBigqueryData = versionData.sqlalchemyBigquery;

  parallel-web = python3.pkgs.buildPythonPackage rec {
    pname = "parallel-web";
    version = parallelWebData.version;
    pyproject = true;

    src = fetchFromGitHub {
      owner = "parallel-web";
      repo = "parallel-sdk-python";
      tag = "v${version}";
      hash = parallelWebData.hash;
    };

    build-system = with python3.pkgs; [
      hatchling
      hatch-fancy-pypi-readme
    ];

    # Upstream pins build-system dependencies more tightly than nixpkgs does.
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
      description = "The official Python library for the Parallel API";
      homepage = "https://github.com/parallel-web/parallel-sdk-python";
      license = licenses.mit;
      sourceProvenance = with sourceTypes; [ fromSource ];
      platforms = platforms.all;
    };
  };

  sqlalchemy-bigquery = python3.pkgs.buildPythonPackage rec {
    pname = "sqlalchemy-bigquery";
    version = sqlalchemyBigqueryData.version;
    pyproject = true;

    src = fetchFromGitHub {
      owner = "googleapis";
      repo = "python-bigquery-sqlalchemy";
      tag = "v${version}";
      hash = sqlalchemyBigqueryData.hash;
    };

    build-system = with python3.pkgs; [ setuptools ];

    dependencies = with python3.pkgs; [
      google-api-core
      google-auth
      google-cloud-bigquery
      packaging
      sqlalchemy
    ];

    pythonImportsCheck = [ "sqlalchemy_bigquery" ];

    meta = with lib; {
      description = "SQLAlchemy dialect for BigQuery";
      homepage = "https://github.com/googleapis/python-bigquery-sqlalchemy";
      license = licenses.mit;
      sourceProvenance = with sourceTypes; [ fromSource ];
      platforms = platforms.all;
    };
  };

  # packages/parallel-cli/update.py keeps these sidecar-managed embedded pins
  # aligned with the minimum versions required by upstream. Embedded pins
  # advance only when upstream raises its declared minimum; they never chase
  # the latest release independently.

  # The nixpkgs Snowflake connector package is source-built from GitHub already,
  # but its upstream test suite exercises local socket/network behavior that is
  # not reliable in our build sandbox. Keep the package and disable checks here
  # instead of dropping Snowflake support from the CLI surface.
  #
  # Upstream 4.3.0's setup.py promotes the `boto` extra into install_requires
  # at egg_info time unless SNOWFLAKE_NO_BOTO is set, which makes
  # pythonRuntimeDepsCheckHook fail because nixpkgs only lists boto3/botocore
  # as optional-dependencies. parallel-cli's Snowflake integration does not
  # touch the S3/STS code paths, so opt out of the boto extra.
  snowflake-connector-python = python3.pkgs.snowflake-connector-python.overridePythonAttrs (old: {
    doCheck = false;
    env = (old.env or { }) // {
      SNOWFLAKE_NO_BOTO = "1";
    };
  });
in
python3.pkgs.buildPythonApplication rec {
  pname = "parallel-cli";
  inherit version;
  pyproject = true;

  src = fetchFromGitHub {
    owner = "parallel-web";
    repo = "parallel-web-tools";
    tag = "v${version}";
    inherit hash;
  };

  build-system = with python3.pkgs; [ hatchling ];

  # Package the source CLI with the dependency set needed for the full upstream
  # [all] extra: cli, polars, duckdb, snowflake, bigquery. Spark is dev-only.
  dependencies = with python3.pkgs; [
    parallel-web
    sqlalchemy-bigquery
    snowflake-connector-python
    click
    duckdb
    httpx
    nest-asyncio
    polars
    pyarrow
    pyyaml
    python-dotenv
    questionary
    rich
    sqlalchemy
  ];

  pythonImportsCheck = [
    "parallel_web_tools"
    "parallel_web_tools.integrations.snowflake"
    "snowflake.connector"
    "sqlalchemy_bigquery"
  ];

  doInstallCheck = true;
  nativeInstallCheckInputs = [
    versionCheckHook
    versionCheckHomeHook
  ];
  versionCheckProgramArg = [ "--version" ];

  passthru.category = "Utilities";

  passthru.updater = mkUpdater { kind = "script"; };

  meta = with lib; {
    description = "AI-powered web search, extraction, and research CLI from Parallel";
    homepage = "https://github.com/parallel-web/parallel-web-tools";
    changelog = "https://github.com/parallel-web/parallel-web-tools/releases/tag/v${version}";
    license = licenses.mit;
    sourceProvenance = with sourceTypes; [ fromSource ];
    maintainers = with flake.lib.maintainers; [ SecBear ];
    mainProgram = "parallel-cli";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
      "aarch64-darwin"
    ];
  };
}
