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
  version = "0.6.3";
  pyproject = true;

  src = fetchPypi {
    pname = "orbi_cli";
    inherit version;
    hash = "sha256-xRumRY2fu/drtlKd4wPXTvFB2yfyfUmw6ID9IsVENSI=";
  };

  build-system = [ python3.pkgs.setuptools ];

  # Orbi shells out to gh, git and pi (the coding agent it drives).
  makeWrapperArgs = [
    "--prefix"
    "PATH"
    ":"
    (lib.makeBinPath [
      gh
      git
      pi
    ])
  ];

  pythonImportsCheck = [ "orbi" ];

  nativeInstallCheckInputs = [ versionCheckHook ];

  passthru.category = "Workflow & Project Management";

  meta = {
    description = "Turns labeled GitHub issues into reviewed, merged pull requests by running the Pi coding agent";
    homepage = "https://orbi.build";
    changelog = "https://github.com/orbi-build/orbi/releases/tag/v${version}";
    # Upstream offers AGPL-3.0-only OR the Sustainable Use License 1.0.
    license = lib.licenses.agpl3Only;
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
    maintainers = with flake.lib.maintainers; [ xqliu ];
    mainProgram = "orbi";
  };
}
