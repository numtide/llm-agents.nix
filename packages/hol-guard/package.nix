{
  lib,
  flake,
  python3,
  fetchPypi,
  versionCheckHook,
}:

python3.pkgs.buildPythonApplication rec {
  pname = "hol-guard";
  version = "3.0.192";
  pyproject = true;

  src = fetchPypi {
    pname = "hol_guard";
    inherit version;
    hash = "sha256-3KtNGje02x++eJDvsrwz2kb0x82b0fI0devWoxNpO6g=";
  };

  postPatch = ''
    substituteInPlace pyproject.toml --replace-fail '"hatchling<1.31"' '"hatchling"'
  '';

  build-system = [ python3.pkgs.hatchling ];

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
