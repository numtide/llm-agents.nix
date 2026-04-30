{
  lib,
  python3,
  fetchFromGitHub,
}:

python3.pkgs.buildPythonApplication rec {
  pname = "hermes-hud";
  version = "0.5.0";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "joeynyc";
    repo = "hermes-hud";
    rev = "v${version}";
    hash = "sha256-Osn/+7qnRQORBJLWgngLT2BU0EVu2xyRN7De619IDNI=";
  };

  build-system = with python3.pkgs; [
    setuptools
    wheel
  ];

  dependencies = with python3.pkgs; [
    pyfiglet
    pyyaml
    textual
  ];

  pythonImportsCheck = [ "hermes_hud" ];

  passthru.category = "AI Assistants";

  meta = with lib; {
    description = "TUI consciousness monitor for Hermes Agent";
    homepage = "https://github.com/joeynyc/hermes-hud";
    changelog = "https://github.com/joeynyc/hermes-hud/releases/tag/v${version}";
    license = licenses.mit;
    sourceProvenance = with sourceTypes; [ fromSource ];
    maintainers = [ ];
    platforms = platforms.unix;
    mainProgram = "hermes-hud";
  };
}
