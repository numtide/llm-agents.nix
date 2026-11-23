{
  lib,
  python3,
  fetchFromGitHub,
  installAgentSkills,
  versionCheckHook,
  versionCheckHomeHook,
}:

python3.pkgs.buildPythonApplication (finalAttrs: {
  pname = "apm";
  version = "0.38.0";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "microsoft";
    repo = "apm";
    tag = "v${finalAttrs.version}";
    hash = "sha256-3rMTcqLq/mjOaXUS4/9LRI1vvoi3ad8gIMyCZmGOCPg=";
  };

  build-system = with python3.pkgs; [
    setuptools
  ];

  dependencies = with python3.pkgs; [
    click
    colorama
    filelock
    gitpython
    python-frontmatter
    pyyaml
    requests
    rich
    rich-click
    ruamel-yaml
    toml
    tomlkit
    # truststore has no runtime dependencies; nixpkgs lists its test
    # dependencies (aiohttp, httpx, pyopenssl, trustme) as such.
    (truststore.overridePythonAttrs { dependencies = [ ]; })
    watchdog
    websockets
  ];

  # websockets<17 pin; the sync client apm uses is unchanged in 17.
  pythonRelaxDeps = [ "websockets" ];

  # apm never imports these: the optional `llm` runtime is an executable it
  # looks up on PATH, like copilot or codex.
  pythonRemoveDeps = [
    "llm"
    "llm-github-models"
  ];

  pythonImportsCheck = [ "apm_cli" ];

  nativeBuildInputs = [ installAgentSkills ];

  doInstallCheck = true;
  nativeInstallCheckInputs = [
    versionCheckHook
    versionCheckHomeHook
  ];
  versionCheckProgramArg = [ "--version" ];

  # The usage guide is hidden under .apm; exclude templates and test fixtures.
  dontInstallAgentSkills = true;
  postInstall = ''
    installSkill packages/apm-guide/.apm/skills/apm-usage
  '';

  postInstallCheck = ''
    test -f "$out/share/skills/apm/apm-usage/SKILL.md"
    test -f "$out/share/skills/apm/apm-usage/commands.md"
  '';

  passthru.category = "Utilities";

  meta = with lib; {
    description = "Agent Package Manager — dependency manager for AI agents";
    homepage = "https://github.com/microsoft/apm";
    changelog = "https://github.com/microsoft/apm/releases/tag/v${finalAttrs.version}";
    license = licenses.mit;
    sourceProvenance = with sourceTypes; [ fromSource ];
    platforms = platforms.all;
    mainProgram = "apm";
  };
})
