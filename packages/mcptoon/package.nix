{
  lib,
  python3,
  fetchFromGitHub,
}:

python3.pkgs.buildPythonApplication rec {
  pname = "mcptoon";
  version = "0.7.10";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "activeing123";
    repo = "mcptoon";
    tag = "v${version}";
    hash = "sha256-YcpizgfccgSl77J15WE2UOeD6w2qAGQUBYQPFYaGslc=";
  };

  # Upstream tags releases without bumping __version__ (v0.2.2 still
  # says 0.2.1), and the CLI banner prints it. Align it with the tag.
  postPatch = ''
    sed -i -E 's/^__version__ = ".*"/__version__ = "${version}"/' src/mcptoon/__init__.py
  '';

  build-system = with python3.pkgs; [
    setuptools
  ];

  pythonImportsCheck = [ "mcptoon" ];

  nativeCheckInputs = with python3.pkgs; [
    pytestCheckHook
  ];

  # config.py creates ~/.config/mcptoon at import time; the tests
  # import it, so they need a writable HOME.
  preCheck = ''
    export HOME=$TMPDIR
  '';

  passthru.category = "Utilities";

  meta = with lib; {
    description = "Token-efficient MCP CLI client that converts tool discovery and results to compact TOON output";
    homepage = "https://github.com/activeing123/mcptoon";
    changelog = "https://github.com/activeing123/mcptoon/releases/tag/v${version}";
    license = licenses.asl20;
    sourceProvenance = with sourceTypes; [ fromSource ];
    maintainers = with maintainers; [ zimbatm ];
    mainProgram = "mcptoon";
    platforms = platforms.all;
  };
}
