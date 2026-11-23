{
  lib,
  python3,
  fetchFromGitHub,
}:

let
  python = python3.override {
    self = python;
    packageOverrides = final: prev: {
      # fastmcp-slim 3.4.7 is marked broken against mcp >= 2, so pin the
      # whole scope to mcp 1.x where nixpkgs ships it as `mcp_1`. Drop this
      # once fastmcp 4.x lands (NixOS/nixpkgs#563493). Pins that predate
      # `mcp_1` still carry mcp 1.x as `mcp`.
      mcp = final.mcp_1 or prev.mcp;

      # fastmcp test suite hangs on x86_64-linux with current nixpkgs pin
      # (some async tests block past the 3h builder timeout). Skip checks
      # since we only need it as a runtime dependency.
      fastmcp = prev.fastmcp.overridePythonAttrs { doCheck = false; };
    };
  };

in
python.pkgs.buildPythonApplication rec {
  pname = "code-review-graph";
  version = "2.4.0";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "tirth8205";
    repo = "code-review-graph";
    tag = "v${version}";
    hash = "sha256-prDngvKn/a4V6iegxqiZMrC+OmO+ywM9yNE/mf8BKN4=";
  };

  build-system = with python.pkgs; [
    hatchling
  ];

  # Upstream pins tree-sitter-language-pack <1 and watchdog <6, but nixpkgs
  # has advanced to 1.x and 6.x. The runtime deps check is overly strict.
  pypaBuildFlags = [ "--skip-dependency-check" ];

  dependencies = with python.pkgs; [
    mcp
    fastmcp
    tree-sitter
    tree-sitter-language-pack
    networkx
    watchdog
  ];

  # The parser probe spawns `sys.executable`, which lacks the wrapper's
  # sys.path; use an interpreter that ships the language pack (#7216).
  postPatch = ''
    substituteInPlace code_review_graph/parser.py \
      --replace-fail '[sys.executable, "-c", code, grammar]' \
        '["${
          python.withPackages (ps: [ ps.tree-sitter-language-pack ])
        }/bin/python", "-c", code, grammar]'
  '';

  # Relax version constraints — nixpkgs versions are newer but compatible.
  # fastmcp: upstream v2.3.6 pins `<3` but main already moved to `>=3.2.4`
  # (no API breaks for the tool/prompt decorators used here), so accept the
  # nixpkgs 3.x build until the next tagged release.
  pythonRelaxDeps = [
    "fastmcp"
    "tree-sitter"
    "tree-sitter-language-pack"
    "watchdog"
  ];

  pythonImportsCheck = [ "code_review_graph" ];

  passthru.category = "Code Review";

  meta = with lib; {
    description = "Local knowledge graph for AI coding agents — builds persistent map of your codebase for token-efficient code reviews";
    homepage = "https://github.com/tirth8205/code-review-graph";
    changelog = "https://github.com/tirth8205/code-review-graph/releases/tag/v${version}";
    license = licenses.mit;
    sourceProvenance = with sourceTypes; [ fromSource ];
    maintainers = with maintainers; [ aldoborrero ];
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
      "aarch64-darwin"
    ];
    mainProgram = "code-review-graph";
  };
}
