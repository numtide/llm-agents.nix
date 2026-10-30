{
  lib,
  flake,
  python3,
  hindsight,
}:

python3.pkgs.buildPythonPackage {
  pname = "hindsight-client";
  inherit (hindsight) version src;

  sourceRoot = "${hindsight.src.name}/hindsight-clients/python";
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
  };

  meta = {
    description = "Python client for the Hindsight agent memory server";
    inherit (hindsight.meta)
      homepage
      changelog
      license
      sourceProvenance
      ;
    maintainers = with flake.lib.maintainers; [ wanderer ];
    platforms = lib.platforms.all;
  };
}
