{
  lib,
  flake,
  python3,
  fetchFromGitHub,
}:

python3.pkgs.buildPythonPackage rec {
  pname = "hindsight-client";
  version = "1.1.0";

  src = fetchFromGitHub {
    owner = "vectorize-io";
    repo = "hindsight";
    tag = "v${version}";
    hash = "sha256-0+BuUhlf3mljlo9F9cVLcnOORZhMlK1mFY7Cqem6oYs=";
  };

  sourceRoot = "${src.name}/hindsight-clients/python";
  pyproject = true;

  build-system = [ python3.pkgs.hatchling ];

  dependencies = with python3.pkgs; [
    urllib3
    python-dateutil
    aiohttp
    aiohttp-retry
    pydantic
    typing-extensions
    yarl
  ];

  # The full test suite requires a running Hindsight API server.
  doCheck = false;

  pythonImportsCheck = [
    "hindsight_client"
    "hindsight_client_api"
  ];

  passthru = {
    category = "AI Assistants";
    hideFromDocs = true;
    updateEvenIfHidden = true;
  };

  meta = with lib; {
    description = "Python client for the Hindsight agent memory server";
    homepage = "https://github.com/vectorize-io/hindsight";
    changelog = "https://github.com/vectorize-io/hindsight/releases/tag/v${version}";
    license = licenses.mit;
    sourceProvenance = with sourceTypes; [ fromSource ];
    maintainers = with flake.lib.maintainers; [ wanderer ];
    platforms = platforms.all;
  };
}
