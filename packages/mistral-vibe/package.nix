{
  lib,
  python3,
  fetchFromGitHub,
  fetchPypi,
  mistralai,
  agent-client-protocol,
  rustPlatform,
  cargo,
  rustc,
  maturin,
  versionCheckHook,
  versionCheckHomeHook,
}:

let
  textual-speedups = python3.pkgs.buildPythonPackage rec {
    pname = "textual-speedups";
    version = "0.2.1";
    pyproject = true;

    src = fetchPypi {
      pname = "textual_speedups";
      inherit version;
      hash = "sha256-cs8Pe97t4BU2e1m3C89yS6LDCAqGQevF65SzatFTaCQ=";
    };

    cargoDeps = rustPlatform.fetchCargoVendor {
      inherit src;
      name = "${pname}-${version}";
      hash = "sha256-Bz4ocEziOlOX4z5F9EDry99YofeGyxL/6OTIf/WEgK4=";
    };

    nativeBuildInputs = [
      rustPlatform.cargoSetupHook
      rustPlatform.maturinBuildHook
      cargo
      rustc
      maturin
    ];

    pythonImportsCheck = [ "textual_speedups" ];

    meta = with lib; {
      description = "Optional Rust speedups for Textual TUI framework";
      homepage = "https://github.com/willmcgugan/textual-speedups";
      license = licenses.mit;
      sourceProvenance = with sourceTypes; [ fromSource ];
      platforms = platforms.all;
    };
  };

  tree-sitter-bash = python3.pkgs.buildPythonPackage rec {
    pname = "tree-sitter-bash";
    version = "0.25.1";
    pyproject = true;

    src = fetchPypi {
      pname = "tree_sitter_bash";
      inherit version;
      hash = "sha256-v8C9qne8HobjxmUuWm4UDEDAoWuEGFwrY6182Am4jxQ=";
    };

    build-system = with python3.pkgs; [
      setuptools
    ];

    pythonImportsCheck = [ "tree_sitter_bash" ];

    meta = with lib; {
      description = "Bash grammar for tree-sitter";
      homepage = "https://github.com/tree-sitter/tree-sitter-bash";
      license = licenses.mit;
      sourceProvenance = with sourceTypes; [ fromSource ];
      platforms = platforms.all;
    };
  };

  python = python3.override {
    self = python;
    packageOverrides = _final: _prev: {
      # Inject local packages into the Python package set
      inherit
        mistralai
        agent-client-protocol
        textual-speedups
        tree-sitter-bash
        ;
    };
  };
in
python.pkgs.buildPythonApplication rec {
  pname = "mistral-vibe";
  version = "2.0.0";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "mistralai";
    repo = "mistral-vibe";
    rev = "v${version}";
    hash = "sha256-2waDKL1TWVw2BXl0oqV9+kH86w7dWpz1j61VQSxJW5Q=";
  };

  build-system = with python.pkgs; [
    hatchling
    hatch-vcs
  ];

  dependencies = with python.pkgs; [
    agent-client-protocol
    aiofiles
    httpx
    mcp
    mistralai
    packaging
    pexpect
    pydantic
    pydantic-settings
    pyperclip
    pytest-xdist
    python-dotenv
    rich
    textual
    textual-speedups
    tomli-w
    tree-sitter
    tree-sitter-bash
    watchfiles
  ];

  # Relax version constraints - nixpkgs versions are slightly older but compatible
  pythonRelaxDeps = [
    "agent-client-protocol"
    "mistralai"
    "pydantic"
    "pydantic-settings"
    "watchfiles"
  ];

  pythonImportsCheck = [ "vibe" ];

  doInstallCheck = true;
  nativeInstallCheckInputs = [
    versionCheckHook
    versionCheckHomeHook
  ];
  versionCheckProgramArg = [ "--version" ];

  passthru.category = "AI Coding Agents";

  meta = with lib; {
    description = "Minimal CLI coding agent by Mistral AI - open-source command-line coding assistant powered by Devstral";
    homepage = "https://github.com/mistralai/mistral-vibe";
    license = licenses.asl20;
    sourceProvenance = with sourceTypes; [ fromSource ];
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
      "x86_64-darwin"
      "aarch64-darwin"
    ];
    mainProgram = "vibe";
  };
}
