{
  lib,
  python3,
  fetchurl,
}:

python3.pkgs.buildPythonPackage rec {
  pname = "opentelemetry-exporter-otlp-common";
  version = "0.66b1";
  pyproject = true;

  src = fetchurl {
    url = "https://files.pythonhosted.org/packages/cb/19/41de712173f43057e4532d42ece7d0c6d4210d353e5752433cb14987643f/opentelemetry_exporter_otlp_common-${version}.tar.gz";
    hash = "sha256-axQDSHohhawf60X9VUb9+GMM5xw2vO+q31HiEw6eI/k=";
  };

  build-system = with python3.pkgs; [ hatchling ];

  dependencies = with python3.pkgs; [
    opentelemetry-sdk
    opentelemetry-exporter-http-transport
  ];

  # 0.66b1 pins sdk ~=1.45.1; nixpkgs ships 1.43.0. The exporter uses the
  # stable sdk trace API, the pin is precautionary.
  pythonRelaxDeps = [ "opentelemetry-sdk" ];

  pythonImportsCheck = [ "opentelemetry.exporter.otlp.common" ];

  meta = with lib; {
    description = "OpenTelemetry OTLP HTTP export utilities";
    homepage = "https://github.com/open-telemetry/opentelemetry-python/tree/main/exporter/opentelemetry-exporter-otlp-common";
    changelog = "https://github.com/open-telemetry/opentelemetry-python/releases";
    license = licenses.asl20;
    sourceProvenance = with sourceTypes; [ fromSource ];
    platforms = platforms.all;
  };
}
