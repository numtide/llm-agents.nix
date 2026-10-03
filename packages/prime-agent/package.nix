{
  lib,
  fetchFromGitHub,
  flake,
  makeWrapper,
  python3,
  rustPlatform,
  versionCheckHook,
  versionCheckHomeHook,
}:

rustPlatform.buildRustPackage (finalAttrs: {
  pname = "prime-agent";
  version = "0.9.8-unstable-2026-10-01";

  src = fetchFromGitHub {
    owner = "PrimeIntellect-ai";
    repo = "prime-agent";
    rev = "3358e0016bce7cf34a195af58bbd91a26e17d694";
    hash = "sha256-l5JwBoltANccY0tonNufzTjl6VHg5VwafCeJ5vcnHwo=";
  };

  cargoHash = "sha256-zk+Oxw04EudoDWBM0vdkR4HE1HvYanhvn7s2a9tui9U=";
  cargoBuildFlags = [
    "-p"
    "pa-cli"
    "--bin"
    "prime-agent"
  ];

  nativeBuildInputs = [
    makeWrapper
    python3
  ];

  postBuild = ''
    python3 scripts/release/bundle_catalog.py generate --fixture \
      --out target/catalog-assets
  '';

  installPhase = ''
    runHook preInstall

    packageDir=$out/share/prime-agent
    mkdir -p $out/bin "$packageDir"
    binary="$(find target -type f -path "*/${finalAttrs.cargoBuildType}/prime-agent" -print -quit)"
    test -n "$binary"
    install -Dm755 "$binary" "$packageDir/prime-agent"
    cp -r prime-agent-runtime skills "$packageDir/"
    install -Dm644 README.md LICENSE target/catalog-assets/*.json \
      -t "$packageDir"

    cat > "$packageDir/package.json" <<'JSON'
    {
      "name": "prime-agent",
      "version": "${finalAttrs.version}",
      "description": "Prime Agent: the RLM coding agent (Rust build)",
      "bin": { "prime-agent": "prime-agent" },
      "piConfig": { "name": "prime-agent", "configDir": ".prime/agent" },
      "commit": "${finalAttrs.src.rev}"
    }
    JSON

    makeWrapper "$packageDir/prime-agent" $out/bin/prime-agent \
      --set PI_PACKAGE_DIR "$packageDir" \
      --set PRIME_AGENT_KERNEL_PYTHON ${finalAttrs.passthru.pythonRuntime}/bin/python3

    runHook postInstall
  '';

  # Upstream snapshot tests depend on terminal color and width detection.
  doCheck = false;

  doInstallCheck = true;
  nativeInstallCheckInputs = [
    versionCheckHook
    versionCheckHomeHook
  ];

  installCheckPhase = ''
    runHook preInstallCheck

    expectedSkills="agent-message agent-observe attach-image compact edit goal mcp prime-intellect refine rlm-heartbeat skill-creator websearch"
    installedSkills="$(find "$out/share/prime-agent/skills" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | sort | tr '\n' ' ' | sed 's/ $//')"
    test "$installedSkills" = "$expectedSkills"

    ${finalAttrs.passthru.pythonRuntime}/bin/python3 <<'PY'
    import inspect
    import importlib.metadata

    import agent_message, agent_observe, attach_image, compact, edit, goal
    import refine, rlm, rlm_heartbeat, websearch

    assert callable(rlm.spawn)
    assert inspect.signature(rlm.spawn).parameters["name"].default is inspect.Parameter.empty
    assert not hasattr(rlm, "run")
    assert callable(rlm.host_request)
    assert callable(rlm.create_session)
    assert callable(rlm.collect)
    assert callable(rlm.progress_note)
    assert callable(agent_observe.list_agents)
    assert callable(agent_observe.get_agent)
    assert callable(agent_observe.recent_messages)
    assert callable(refine.run)
    assert callable(refine.status)

    import rlm.mcp
    for name in ["list_plugins", "search_plugins", "list_connections", "search_tools", "describe_tool", "list_tools", "call_tool"]:
        assert callable(getattr(rlm.mcp, name, None)), name

    distributions = importlib.metadata.packages_distributions()["rlm"]
    assert distributions == ["prime-agent-runtime"], distributions
    PY

    runHook postInstallCheck
  '';

  passthru =
    let
      # Keep MCP 2 private to Prime Agent; reuse nixpkgs HTTP clients and build tools.
      # Every runtime/skill below uses this same Python package set.
      python = python3.override (pythonArgs: {
        self = python;
        packageOverrides = lib.composeExtensions (pythonArgs.packageOverrides or (_: _: { })) (
          pyFinal: pyPrev: {
            mcp-types = pyFinal.buildPythonPackage {
              pname = "mcp-types";
              version = "2.0.0";
              src = mcpSrc;
              sourceRoot = "${mcpSrc.name}/src/mcp-types";
              pyproject = true;
              build-system = with pyFinal; [
                hatchling
                uv-dynamic-versioning
              ];
              dependencies = with pyFinal; [
                pydantic
                typing-extensions
              ];
              pythonImportsCheck = [ "mcp_types" ];
              meta = pyPrev.mcp.meta // {
                description = "Model Context Protocol wire types";
                changelog = "https://github.com/modelcontextprotocol/python-sdk/releases/tag/v2.0.0";
              };
            };

            # Use the SDK's exact dependencies without inherited substitutions.
            mcp = pyFinal.buildPythonPackage {
              pname = "mcp";
              version = "2.0.0";
              src = mcpSrc;
              pyproject = true;
              build-system = with pyFinal; [
                hatchling
                uv-dynamic-versioning
              ];
              dependencies =
                with pyFinal;
                [
                  anyio
                  httpx2
                  jsonschema
                  mcp-types
                  opentelemetry-api
                  pydantic
                  pyjwt
                  python-multipart
                  sse-starlette
                  starlette
                  typing-extensions
                  typing-inspection
                  uvicorn
                ]
                ++ pyFinal.pyjwt.optional-dependencies.crypto;
              pythonImportsCheck = [
                "mcp"
                "mcp.client.stdio"
                "mcp.client.streamable_http"
              ];
              meta = pyPrev.mcp.meta // {
                changelog = "https://github.com/modelcontextprotocol/python-sdk/releases/tag/v2.0.0";
              };
            };
          }
        );
      });
      mcpSrc = fetchFromGitHub {
        owner = "modelcontextprotocol";
        repo = "python-sdk";
        tag = "v2.0.0";
        hash = "sha256-baeceVB9PC+f3vQO1AaDHflOJ7oD7u7ylXUkVvusT/o=";
      };
    in
    {
      category = "AI Coding Agents";

      primeAgentRuntime = python.pkgs.buildPythonPackage {
        pname = "prime-agent-runtime";
        version = "0.1.0";
        src = "${finalAttrs.src}/prime-agent-runtime";
        pyproject = true;
        build-system = [ python.pkgs.hatchling ];
        dependencies = with python.pkgs; [
          mcp
          tyro
        ];
        pythonImportsCheck = [ "rlm" ];
      };

      pythonSkills =
        let
          buildSkill =
            {
              directory,
              version,
              pname ? directory,
              dependencies ? [ ],
            }:
            python.pkgs.buildPythonPackage {
              inherit pname version dependencies;
              src = "${finalAttrs.src}/skills/${directory}";
              pyproject = true;
              build-system = [ python.pkgs.hatchling ];
              pythonImportsCheck = [ (builtins.replaceStrings [ "-" ] [ "_" ] directory) ];
            };
          runtime = finalAttrs.passthru.primeAgentRuntime;
        in
        # update.py relies on adjacent directory and version fields to update
        # each bundled skill independently when upstream versions diverge.
        [
          (buildSkill {
            directory = "agent-message";
            version = "0.1.0";
            dependencies = [ runtime ];
          })
          (buildSkill {
            directory = "agent-observe";
            version = "0.1.0";
            dependencies = [ runtime ];
          })
          (buildSkill {
            directory = "attach-image";
            version = "0.1.0";
            pname = "prime-agent-skill-attach-image";
            dependencies = with python.pkgs; [
              pillow
              runtime
            ];
          })
          (buildSkill {
            directory = "compact";
            version = "0.1.0";
            dependencies = [ runtime ];
          })
          (buildSkill {
            directory = "edit";
            version = "0.1.0";
            dependencies = [ runtime ];
          })
          (buildSkill {
            directory = "goal";
            version = "0.1.0";
            dependencies = [ runtime ];
          })
          (buildSkill {
            directory = "refine";
            version = "0.1.0";
            dependencies = [ runtime ];
          })
          (buildSkill {
            directory = "rlm-heartbeat";
            version = "0.1.0";
            dependencies = [ runtime ];
          })
          (buildSkill {
            directory = "websearch";
            version = "0.1.0";
            pname = "prime-agent-skill-websearch";
            dependencies = with python.pkgs; [
              httpx
              runtime
            ];
          })
        ];

      pythonRuntime = python.withPackages (
        ps:
        (with ps; [
          beautifulsoup4
          dill
          httpx
          ipykernel
          ipython
          lxml
          mcp
          nest-asyncio
          numpy
          pandas
          pillow
          pydantic
          python-dotenv
          pyyaml
          requests
          scipy
          tomli
          tyro
        ])
        ++ [ finalAttrs.passthru.primeAgentRuntime ]
        ++ finalAttrs.passthru.pythonSkills
      );
    };

  meta = {
    description = "A self-improving RLM agent for coding workflows and long-running autonomous tasks.";
    homepage = "https://github.com/PrimeIntellect-ai/prime-agent";
    changelog = "https://github.com/PrimeIntellect-ai/prime-agent/commits/${finalAttrs.src.rev}";
    license = lib.licenses.mit;
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
    maintainers = with flake.lib.maintainers; [ mulatta ];
    mainProgram = "prime-agent";
    platforms = lib.platforms.unix;
  };
})
