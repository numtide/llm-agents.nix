{
  lib,
  python3,
  fetchFromGitHub,
  fetchPypi,
  versionCheckHook,
  versionCheckHomeHook,
}:

let
  azure-ai-inference = python3.pkgs.buildPythonPackage rec {
    pname = "azure-ai-inference";
    version = "1.0.0b9";
    pyproject = true;

    src = fetchPypi {
      pname = "azure_ai_inference";
      inherit version;
      hash = "sha256-H+tJa9hLAe4mkb78BDWPol18NE2CiOmTZEOIWa181aQ=";
    };

    build-system = with python3.pkgs; [
      setuptools
    ];

    dependencies = with python3.pkgs; [
      azure-core
      isodate
      typing-extensions
    ];

    pythonImportsCheck = [ "azure.ai.inference" ];

    # Tests require network access and Azure credentials
    doCheck = false;

    meta = with lib; {
      description = "Microsoft Azure AI Inference Client Library for Python";
      homepage = "https://github.com/Azure/azure-sdk-for-python";
      license = licenses.mit;
      sourceProvenance = with sourceTypes; [ fromSource ];
      platforms = platforms.all;
    };
  };

  llm-github-models = python3.pkgs.buildPythonPackage rec {
    pname = "llm-github-models";
    version = "0.18.0";
    pyproject = true;

    src = fetchPypi {
      pname = "llm_github_models";
      inherit version;
      hash = "sha256-t3iqb6Q+U+yzuGj8+YdbwOdgp3Sh+tduqQeiaVgqIEM=";
    };

    build-system = with python3.pkgs; [
      setuptools
    ];

    dependencies = with python3.pkgs; [
      llm
      aiohttp
      azure-ai-inference
    ];

    pythonImportsCheck = [ "llm_github_models" ];

    # Tests require GitHub API token
    doCheck = false;

    meta = with lib; {
      description = "LLM plugin for GitHub Models";
      homepage = "https://github.com/tonybaloney/llm-github-models";
      license = licenses.asl20;
      sourceProvenance = with sourceTypes; [ fromSource ];
      platforms = platforms.all;
    };
  };
in
python3.pkgs.buildPythonApplication (finalAttrs: {
  pname = "apm";
  version = "0.24.0";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "microsoft";
    repo = "apm";
    tag = "v${finalAttrs.version}";
    hash = "sha256-fUq32fFp9TWKQMZnP9ZtdcOTEujS6bklInVAGTSDaEE=";
  };

  build-system = with python3.pkgs; [
    setuptools
  ];

  dependencies = with python3.pkgs; [
    click
    colorama
    filelock
    gitpython
    llm
    llm-github-models
    python-frontmatter
    pyyaml
    requests
    rich
    rich-click
    ruamel-yaml
    toml
    watchdog
  ];

  pythonImportsCheck = [ "apm_cli" ];

  doInstallCheck = true;
  nativeInstallCheckInputs = [
    versionCheckHook
    versionCheckHomeHook
  ];
  versionCheckProgramArg = [ "--version" ];

  passthru.category = "Utilities";

  meta = with lib; {
    description = "Agent Package Manager — dependency manager for AI agents";
    homepage = "https://github.com/microsoft/apm";
    changelog = "https://github.com/microsoft/apm/releases/tag/v${finalAttrs.version}";
    license = licenses.mit;
    sourceProvenance = with sourceTypes; [ fromSource ];
    platforms = platforms.all;
    mainProgram = "apm";
  };
})
