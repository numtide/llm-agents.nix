{
  lib,
  flake,
  python3,
  fetchPypi,
  versionCheckHook,
  gh,
  git,
  pi,
}:

python3.pkgs.buildPythonApplication rec {
  pname = "orbi-cli";
  version = "0.7.15";
  pyproject = true;

  src = fetchPypi {
    pname = "orbi_cli";
    inherit version;
    hash = "sha256-uyI7OazLzBZadMQeKuXQnwvRUUq6ksfy4Clfr8mych4=";
  };

  build-system = [ python3.pkgs.setuptools ];

  # Suffix, so that the user's own gh, git and pi win.
  makeWrapperArgs = [
    "--suffix"
    "PATH"
    ":"
    (lib.makeBinPath [
      gh
      git
      pi
    ])
  ];

  # The sdist ships tests/ without its conftest.py and helper modules.

  pythonImportsCheck = [ "orbi" ];

  nativeInstallCheckInputs = [ versionCheckHook ];

  passthru.category = "Workflow & Project Management";

  meta = {
    description = "Run the Pi coding agent on labeled GitHub issues and merge the reviewed pull requests";
    homepage = "https://orbi.build";
    changelog = "https://github.com/orbi-build/orbi/releases/tag/v${version}";
    # Upstream offers AGPL-3.0-only OR the Sustainable Use License 1.0.
    license = lib.licenses.agpl3Only;
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
    maintainers = with flake.lib.maintainers; [ xqliu ];
    mainProgram = "orbi";
    platforms = lib.platforms.unix;
  };
}
