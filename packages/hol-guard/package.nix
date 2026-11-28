{
  lib,
  flake,
  python3,
  fetchPypi,
  versionCheckHook,
}:

python3.pkgs.buildPythonApplication rec {
  pname = "hol-guard";
  version = "3.61.0";
  format = "wheel";

  # PyPI stopped shipping an sdist with 3.41.0; use the pure-Python wheel.
  src = fetchPypi {
    pname = "hol_guard";
    inherit version format;
    dist = "py3";
    python = "py3";
    hash = "sha256-hW9iyXoSowv/1px8dvEbW9x1FsWLceKVNbunZHVbz7U=";
  };

  dependencies = with python3.pkgs; [
    cryptography
    idna
    jsonschema
    keyring
    mcp
    packaging
    publicsuffixlist
    pyyaml
    regex
    requests
    rich
    sigstore
    tomlkit
    typing-extensions
  ];

  pythonRelaxDeps = true;

  pythonImportsCheck = [ "codex_plugin_scanner" ];

  nativeInstallCheckInputs = [ versionCheckHook ];

  passthru.category = "Utilities";

  meta = {
    description = "Open-source antivirus and runtime protection for AI agents";
    homepage = "https://hol.org/guard";
    changelog = "https://github.com/hashgraph-online/hol-guard/releases/tag/v${version}";
    license = lib.licenses.asl20;
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
    maintainers = with flake.lib.maintainers; [ kantorcodes ];
    mainProgram = "hol-guard";
  };
}
