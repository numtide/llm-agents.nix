{
  lib,
  buildNpmPackage,
  cairo,
  fetchFromGitHub,
  flake,
  giflib,
  libjpeg,
  librsvg,
  makeWrapper,
  nodejs_22,
  pango,
  pixman,
  pkg-config,
  python3,
  versionCheckHook,
  versionCheckHomeHook,
}:

buildNpmPackage (finalAttrs: {
  npmDepsFetcherVersion = 2;
  pname = "prime-agent";
  version = "0.9.6";

  src = fetchFromGitHub {
    owner = "PrimeIntellect-ai";
    repo = "prime-agent";
    tag = "v${finalAttrs.version}";
    hash = "sha256-X54K6AdJ2hrEkKOVl6sk8kt8ZK86s1WxafqN2WJqp1c=";
  };

  nodejs = nodejs_22;
  npmDepsHash = "sha256-oXnZ2G4L8TeSdfP4VFfPoTMBVDINN83Tg2ya/OFG0rw=";

  nativeBuildInputs = [
    makeWrapper
    pkg-config
  ];

  buildInputs = [
    cairo
    giflib
    libjpeg
    librsvg
    pango
    pixman
  ];

  # npm 11 omits registry metadata for duplicated transitive package versions.
  # fetchNpmDeps needs that metadata to cache every version for offline npm ci.
  postPatch = ''
    cp ${./package-lock.json} package-lock.json

    # nix develop uses a long per-shell TMPDIR on Darwin. Worker socket paths
    # then exceed sockaddr_un.sun_path and Node creates a truncated socket that
    # Prime Agent cannot find. Keep daemon sockets in the short runtime dir.
    substituteInPlace packages/coding-agent/src/modes/daemon/daemon-socket.ts \
      --replace-fail \
        'return join(tmpdir(), `prime-agent-''${suffix}`);' \
        'return join(process.env.XDG_RUNTIME_DIR || "/tmp", `prime-agent-''${suffix}`);'
  '';

  installPhase = ''
    runHook preInstall

    npm prune --omit=dev

    mkdir -p $out/lib/prime-agent $out/bin
    cp -r node_modules $out/lib/prime-agent/
    cp -r packages $out/lib/prime-agent/

    makeWrapper ${lib.getExe nodejs_22} $out/bin/prime-agent \
      --add-flags "$out/lib/prime-agent/packages/coding-agent/dist/bundle/cli.js" \
      --set PI_PACKAGE_DIR "$out/lib/prime-agent/packages/coding-agent" \
      --set PRIME_AGENT_KERNEL_PYTHON ${finalAttrs.passthru.pythonRuntime}/bin/python3

    runHook postInstall
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [
    versionCheckHook
    versionCheckHomeHook
  ];

  postInstallCheck = ''
    expectedSkills="agent-message agent-observe attach-image compact edit goal mcp prime-intellect refine rlm-heartbeat skill-creator websearch"
    installedSkills="$(${finalAttrs.passthru.pythonRuntime}/bin/python3 - "$out/lib/prime-agent/packages/coding-agent/skills" <<'PY'
    from pathlib import Path
    import sys

    root = Path(sys.argv[1])
    print(" ".join(sorted(path.name for path in root.iterdir() if (path / "SKILL.md").is_file())))
    PY
    )"
    test "$installedSkills" = "$expectedSkills"

    ${lib.getExe nodejs_22} --input-type=module - "$out/lib/prime-agent/packages/coding-agent/dist/bundle/amazon-bedrock.js" <<'JS'
    const bedrockProvider = await import(process.argv[2]);

    for (const name of ["streamBedrock", "streamSimpleBedrock"]) {
      if (typeof bedrockProvider[name] !== "function") {
        throw new Error("Bundled Bedrock loader is missing the " + name + " export");
      }
    }
    JS

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

    # The markdown-only mcp skill drives rlm.mcp, which replaced the linear/notion skills.
    import rlm.mcp
    for name in ["list_plugins", "search_plugins", "list_connections", "search_tools", "describe_tool", "list_tools", "call_tool"]:
        assert callable(getattr(rlm.mcp, name, None)), name

    distributions = importlib.metadata.packages_distributions()["rlm"]
    assert distributions == ["prime-agent-runtime"], distributions

    for name, version in {
        "mcp": "2.0.0",
        "mcp-types": "2.0.0",
    }.items():
        installed = list(importlib.metadata.distributions(name=name))
        assert len(installed) == 1, (name, installed)
        assert installed[0].version == version, (name, installed[0].version)

    for name in ["httpx2", "httpcore2"]:
        installed = list(importlib.metadata.distributions(name=name))
        assert len(installed) == 1, (name, installed)

    PY
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
              src = "${finalAttrs.src}/packages/coding-agent/skills/${directory}";
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
    changelog = "https://github.com/PrimeIntellect-ai/prime-agent/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.mit;
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
    maintainers = with flake.lib.maintainers; [ mulatta ];
    mainProgram = "prime-agent";
    platforms = lib.platforms.unix;
  };
})
