{
  lib,
  python3,
  fetchurl,
}:

python3.pkgs.buildPythonPackage rec {
  pname = "opentelemetry-exporter-http-transport";
  version = "0.66b1";
  pyproject = true;

  # The legacy /packages/source/ mirror path 404s for this upload.
  src = fetchurl {
    url = "https://files.pythonhosted.org/packages/62/0c/e3ebdb4b507f66afcc905e6885a4946969bd75b45988492643356fbbdc63/opentelemetry_exporter_http_transport-${version}.tar.gz";
    hash = "sha256-RDCAIDv1JYbOCyrZAeiVHGGDPqsapTmubx8W/p6OeVI=";
  };

  build-system = with python3.pkgs; [ hatchling ];

  dependencies = with python3.pkgs; [ opentelemetry-api ];

  pythonImportsCheck = [ "opentelemetry.exporter.http.transport" ];

  meta = with lib; {
    description = "OpenTelemetry Exporters HTTP transport";
    homepage = "https://github.com/open-telemetry/opentelemetry-python/tree/main/exporter/opentelemetry-exporter-http-transport";
    changelog = "https://github.com/open-telemetry/opentelemetry-python/releases";
    license = licenses.asl20;
    sourceProvenance = with sourceTypes; [ fromSource ];
    platforms = platforms.all;
  };
}
