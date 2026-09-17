{
  lib,
  buildNpmPackage,
  cairo,
  fetchFromGitHub,
  fetchPypi,
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
  version = "0.9.5";

  src = fetchFromGitHub {
    owner = "PrimeIntellect-ai";
    repo = "prime-agent";
    tag = "v${finalAttrs.version}";
    hash = "sha256-BCfiwDhocJJ5PMBnERKGnVsT8lFFuOmiZ6jkoEeHEmY=";
  };

  nodejs = nodejs_22;
  npmDepsHash = "sha256-qx12eAjHQxr0HtBs842XSJk342DNgTUr7bynlDSoYCY=";

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
    expectedSkills="agent-message agent-observe attach-image compact edit goal linear notion prime-intellect refine rlm-heartbeat skill-creator websearch"
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
    import linear, notion, refine, rlm, rlm_heartbeat, websearch

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

    distributions = importlib.metadata.packages_distributions()["rlm"]
    assert distributions == ["prime-agent-runtime"], distributions

    for name, version in {
        "mcp": "2.0.0",
        "mcp-types": "2.0.0",
        "httpx2": "2.12.0",
        "httpcore2": "2.12.0",
    }.items():
        installed = list(importlib.metadata.distributions(name=name))
        assert len(installed) == 1, (name, installed)
        assert installed[0].version == version, (name, installed[0].version)
    PY
  '';

  passthru =
    let
      # Keep MCP 2 and its lock-matched HTTP client private to Prime Agent.
      # Every runtime/skill below uses this same Python package set.
      python = python3.override (pythonArgs: {
        self = python;
        packageOverrides = lib.composeExtensions (pythonArgs.packageOverrides or (_: _: { })) (
          pyFinal: pyPrev: {
            # httpx2 2.12 requires uv-dynamic-versioning >= 0.14, which in turn
            # requires dunamai >= 1.26. Keep their version constraints intact.
            dunamai = pyPrev.dunamai.overridePythonAttrs (old: {
              version = "1.26.1";
              src = fetchPypi {
                pname = "dunamai";
                version = "1.26.1";
                hash = "sha256-O0YAe9ZbALSCTq0KGu42X9ItDsK5whlJfU/Uj1KGDIs=";
              };
              # The VCS integration suites need checkout fixtures, not an sdist.
              doCheck = false;
              meta = old.meta // {
                changelog = "https://github.com/mtkennerly/dunamai/blob/v1.26.1/CHANGELOG.md";
              };
            });

            uv-dynamic-versioning = pyPrev.uv-dynamic-versioning.overridePythonAttrs (old: {
              version = "0.14.0";
              src = fetchPypi {
                pname = "uv_dynamic_versioning";
                version = "0.14.0";
                hash = "sha256-V0+8B+h6zkXAHVWWetO4ZIcSV7mP9bish8JhInrI21s=";
              };
              doCheck = false;
              meta = old.meta // {
                changelog = "https://github.com/ninoseki/uv-dynamic-versioning/releases/tag/v0.14.0";
              };
            });

            httpcore2 = pyFinal.buildPythonPackage {
              pname = "httpcore2";
              version = "2.12.0";
              src = httpx2Src;
              sourceRoot = "${httpx2Src.name}/src/httpcore2";
              pyproject = true;
              build-system = with pyFinal; [
                hatchling
                hatch-fancy-pypi-readme
                uv-dynamic-versioning
              ];
              dependencies = with pyFinal; [
                h11
                truststore
              ];
              pythonImportsCheck = [ "httpcore2" ];
              meta = pyPrev.httpcore2.meta // {
                changelog = "https://github.com/pydantic/httpx2/blob/v2.12.0/src/httpcore2/CHANGELOG.md";
              };
            };

            httpx2 = pyFinal.buildPythonPackage {
              pname = "httpx2";
              version = "2.12.0";
              src = httpx2Src;
              sourceRoot = "${httpx2Src.name}/src/httpx2";
              pyproject = true;
              build-system = with pyFinal; [
                hatchling
                hatch-fancy-pypi-readme
                uv-dynamic-versioning
              ];
              dependencies = with pyFinal; [
                anyio
                httpcore2
                idna
                truststore
                typing-extensions
              ];
              pythonImportsCheck = [ "httpx2" ];
              meta = pyPrev.httpx2.meta // {
                changelog = "https://github.com/pydantic/httpx2/blob/v2.12.0/src/httpx2/CHANGELOG.md";
              };
            };

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
      httpx2Src = fetchFromGitHub {
        owner = "pydantic";
        repo = "httpx2";
        tag = "v2.12.0";
        hash = "sha256-mEJHlG6skKkV90SfjTg+MHGkL7gnf3QLKLbWlTtEb9Q=";
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
            directory = "linear";
            version = "0.1.0";
            pname = "prime-agent-skill-linear";
            dependencies = with python.pkgs; [
              httpx
              mcp
              runtime
            ];
          })
          (buildSkill {
            directory = "notion";
            version = "0.1.0";
            pname = "prime-agent-skill-notion";
            dependencies = with python.pkgs; [
              httpx
              mcp
              runtime
            ];
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
