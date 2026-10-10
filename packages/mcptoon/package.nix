{
  lib,
  python3,
  gitMinimal,
  fetchFromGitHub,
}:

python3.pkgs.buildPythonApplication rec {
  pname = "mcptoon";
  version = "0.8.14";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "activeing123";
    repo = "mcptoon";
    tag = "v${version}";
    hash = "sha256-crnQjFiYj4pBEPfRgeLPXJ8e/VeG7UmDMfSYUsKpWuM=";
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

  nativeCheckInputs = [
    python3.pkgs.pytestCheckHook
    # test_skills.py tombstone tests commit into a scratch repo
    gitMinimal
  ];

  # config.py creates ~/.config/mcptoon at import time; the tests
  # import it, so they need a writable HOME.
  preCheck = ''
    export HOME=$TMPDIR
  '';

  # 0.7.22 added registry searches that query smithery and the MCP
  # registry over the network.
  disabledTests = [
    "test_search_registry_returns_list"
    "test_search_smithery_returns_list"
    "test_search_mcp_registry_returns_list"
    # Expects an editable install, we test the copy in $out.
    "test_packaged_path_resolves_to_the_copy_on_disk"
    # The child exits at once, and the error can be built before the stderr
    # pump thread has buffered anything; loses the race on loaded builders.
    "test_the_node_warning_is_not_the_headline"
  ];

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
