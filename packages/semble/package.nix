{
  lib,
  flake,
  python3,
  fetchFromGitHub,
  fetchPypi,
  makeWrapper,
  versionCheckHomeHook,
}:

let
  inherit (python3.pkgs) buildPythonPackage;

  # Some of semble's direct runtime dependencies are not in nixpkgs.
  # Vendor them inline (same pattern as hermes-agent / parallel-cli), since
  # they have no consumer in this flake other than semble itself.

  model2vec = python3.pkgs.buildPythonPackage rec {
    pname = "model2vec";
    version = "0.8.1";
    pyproject = true;

    src = fetchPypi {
      inherit pname version;
      hash = "sha256-mjXTX2pETkzsGfICfuEGxUllzSa3/UpPACtfPitnd/Q=";
    };

    build-system = with python3.pkgs; [
      setuptools
      setuptools-scm
    ];

    env.SETUPTOOLS_SCM_PRETEND_VERSION = version;

    dependencies = with python3.pkgs; [
      jinja2
      joblib
      numpy
      rich
      safetensors
      setuptools
      tokenizers
      tqdm
    ];

    # Tests require torch + the [distill] / [train] extras, which we do not ship.
    doCheck = false;

    pythonImportsCheck = [ "model2vec" ];

    meta = with lib; {
      description = "Distill a small fast model from any sentence transformer";
      homepage = "https://github.com/MinishLab/model2vec";
      license = licenses.mit;
      sourceProvenance = with sourceTypes; [ fromSource ];
      platforms = platforms.all;
    };
  };

  vicinity = python3.pkgs.buildPythonPackage rec {
    pname = "vicinity";
    version = "0.4.4";
    pyproject = true;

    src = fetchPypi {
      inherit pname version;
      hash = "sha256-Tg/+G7B4zkYE2nYn0vMgw52W0lKUhdDqpeLEyyuzKys=";
    };

    build-system = with python3.pkgs; [
      setuptools
      setuptools-scm
    ];

    env.SETUPTOOLS_SCM_PRETEND_VERSION = version;

    dependencies = with python3.pkgs; [
      numpy
      orjson
      tqdm
    ];

    # Tests require optional backends (hnswlib, faiss, etc.) that we don't ship.
    doCheck = false;

    pythonImportsCheck = [ "vicinity" ];

    meta = with lib; {
      description = "Lightweight nearest neighbors library with flexible backends";
      homepage = "https://github.com/MinishLab/vicinity";
      license = licenses.mit;
      sourceProvenance = with sourceTypes; [ fromSource ];
      platforms = platforms.all;
    };
  };

  # Prebuilt tree-sitter grammar bundle used by semble since 0.5.3. Building
  # it from source would require pinning and compiling ~30 grammar
  # repositories, so use upstream's platform wheels (pure C shared objects
  # loaded via ctypes, no non-libc dependencies).
  grammarWheels = {
    x86_64-linux = {
      platform = "manylinux2014_x86_64";
      hash = "sha256-wEBZXKThF5aaNJgH3OBcGlHbs2joDegLAFU5/YbvnAc=";
    };
    aarch64-linux = {
      platform = "manylinux2014_aarch64";
      hash = "sha256-8k9joE5Wny3iiq85FmyN3djilqoDkKyBbfatG9gU478=";
    };
    aarch64-darwin = {
      platform = "macosx_11_0_arm64";
      hash = "sha256-dy5wEc5eL/XZNHovAnpEfHE9Pw1imD3ThFfwSqIhXGw=";
    };
    x86_64-darwin = {
      platform = "macosx_10_13_x86_64";
      hash = "sha256-Uv5pjx0kieatPmRiyTIud3lnabID90opT4AeWovRDxk=";
    };
  };

  semble-grammars = buildPythonPackage rec {
    pname = "semble-grammars";
    version = "0.1.2";
    format = "wheel";

    src = fetchPypi {
      pname = "semble_grammars";
      inherit version;
      format = "wheel";
      dist = "py3";
      python = "py3";
      abi = "none";
      inherit (grammarWheels.${python3.stdenv.hostPlatform.system}) platform hash;
    };

    dependencies = with python3.pkgs; [
      tree-sitter
    ];

    pythonImportsCheck = [ "semble_grammars" ];

    meta = with lib; {
      description = "Prebuilt tree-sitter grammars for Semble";
      homepage = "https://github.com/MinishLab/semble-grammars";
      license = licenses.mit;
      sourceProvenance = with sourceTypes; [ binaryNativeCode ];
      platforms = builtins.attrNames grammarWheels;
    };
  };
in
python3.pkgs.buildPythonApplication rec {
  pname = "semble";
  version = "0.7.0";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "MinishLab";
    repo = "semble";
    tag = "v${version}";
    hash = "sha256-1nCmCoao1YEy1NAslYQlgoCWgl5YQZX9oOID/Z1WdR8=";
  };

  build-system = with python3.pkgs; [
    setuptools
    setuptools-scm
  ];

  # setuptools_scm normally derives the version from git metadata, but the
  # fetched source tarball has none. Inject the version explicitly so the
  # build doesn't fall back to 0.0.0+unknown (which would also break the
  # static `attr = semble.version.__version__` resolver in pyproject.toml).
  env.SETUPTOOLS_SCM_PRETEND_VERSION = version;

  # Ship the [mcp] extra unconditionally — Nix users get one closure either
  # way, and exposing both binaries (`semble` and `semble-mcp`) is cleaner
  # than gating MCP behind a separate derivation.
  dependencies = with python3.pkgs; [
    model2vec
    vicinity
    numpy
    pathspec
    questionary
    tree-sitter
    semble-grammars
    orjson
    # [mcp] extra:
    mcp
  ];

  nativeBuildInputs = [ makeWrapper ];

  # Upstream's `semble` entry point auto-dispatches to either the CLI or the
  # MCP server based on argv[1]. Expose a second binary that always launches
  # the MCP server so users can wire it into agent configs without relying on
  # the implicit "no-subcommand-means-MCP" behaviour.
  postInstall = ''
    makeWrapper $out/bin/semble $out/bin/semble-mcp
  '';

  pythonImportsCheck = [
    "semble"
    "semble.cli"
    "semble.mcp"
  ];

  # semble does not implement `--version`, so skip versionCheckHook and run
  # an equivalent smoke check ourselves. versionCheckHomeHook is still useful
  # because semble touches ~/.semble for the `savings` ledger.
  doInstallCheck = true;
  nativeInstallCheckInputs = [
    versionCheckHomeHook
  ];
  installCheckPhase = ''
    runHook preInstallCheck
    $out/bin/semble --help >/dev/null
    test -x $out/bin/semble-mcp
    runHook postInstallCheck
  '';

  passthru = {
    category = "Memory & Code Intelligence";
    inherit model2vec vicinity semble-grammars;
  };

  meta = with lib; {
    description = "Fast and accurate local code search for AI agents — CLI and MCP server";
    longDescription = ''
      Semble indexes a codebase using tree-sitter-aware chunking, static
      Model2Vec embeddings, and BM25, then serves results either through the
      `semble` CLI (search, index, find-related, init, savings) or through the
      `semble-mcp` MCP server for agents like Claude Code, Cursor, Codex, and
      OpenCode.
    '';
    homepage = "https://github.com/MinishLab/semble";
    changelog = "https://github.com/MinishLab/semble/releases/tag/v${version}";
    license = licenses.mit;
    sourceProvenance = with sourceTypes; [ fromSource ];
    maintainers = with flake.lib.maintainers; [ murlakatam ];
    mainProgram = "semble";
  };
}
