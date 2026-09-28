{
  lib,
  python3,
  gitMinimal,
  fetchFromGitHub,
}:

python3.pkgs.buildPythonApplication rec {
  pname = "mcptoon";
  version = "0.8.2";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "activeing123";
    repo = "mcptoon";
    tag = "v${version}";
    hash = "sha256-o9BFwPrO2sgDrXgqZunLtnV2YGGnAMqXdBQCjVKU794=";
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
