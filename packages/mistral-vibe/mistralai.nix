{
  lib,
  python3,
  fetchPypi,
}:

python3.pkgs.buildPythonPackage rec {
  pname = "mistralai";
  version = "3.5.0";
  pyproject = true;

  src = fetchPypi {
    inherit pname version;
    hash = "sha256-RUPSQNyLiacAlGf9wYSKqiQhUVEYmDpEdOueN7sJe8Q=";
  };

  build-system = with python3.pkgs; [ hatchling ];

  dependencies = with python3.pkgs; [
    eval-type-backport
    httpx2
    jsonpath-python
    opentelemetry-api
    opentelemetry-semantic-conventions
    pydantic
    python-dateutil
    typing-inspection
  ];

  pythonImportsCheck = [ "mistralai" ];

  meta = with lib; {
    description = "Python Client SDK for the Mistral AI API";
    homepage = "https://github.com/mistralai/client-python";
    changelog = "https://github.com/mistralai/client-python/releases";
    license = licenses.asl20;
    sourceProvenance = with sourceTypes; [ fromSource ];
    platforms = platforms.all;
  };
}
