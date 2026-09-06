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
  version = "0.9.3";

  src = fetchFromGitHub {
    owner = "PrimeIntellect-ai";
    repo = "prime-agent";
    tag = "v${finalAttrs.version}";
    hash = "sha256-7NHaWxQwEwYjxIxLE8B1NR2J7WlY1tKHhmkFnpgcXO8=";
  };

  nodejs = nodejs_22;
  npmDepsHash = "sha256-Op8EHL5pcsgqLngvc2TDsQmbp9mrSSfsftEN7e6w5sg=";

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

    # Release tags include generated model data. Regenerating it would access
    # several model catalog APIs during the sandboxed build.
    substituteInPlace packages/ai/package.json \
      --replace-fail 'npm run generate-models && tsgo' 'tsgo'

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
    ${finalAttrs.passthru.pythonRuntime}/bin/python3 <<'PY'
    import agent_message, agent_observe, attach_image, compact, edit, goal
    import dill, ipykernel, linear, notion, refine, rlm, rlm_heartbeat, websearch

    assert callable(rlm.run)
    assert callable(rlm.host_request)
    assert callable(refine.run)
    assert callable(refine.status)
    PY
  '';

  passthru = {
    category = "AI Coding Agents";

    primeAgentRuntime = python3.pkgs.buildPythonPackage {
      pname = "prime-agent-runtime";
      version = "0.1.0";
      src = "${finalAttrs.src}/prime-agent-runtime";
      pyproject = true;
      build-system = [ python3.pkgs.hatchling ];
      dependencies = with python3.pkgs; [
        ipykernel
        mcp
        nest-asyncio
        tyro
      ];
      # Pins mcp>=2 but rlm/mcp_base.py explicitly supports the 1.x client API.
      pythonRelaxDeps = [ "mcp" ];
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
          python3.pkgs.buildPythonPackage {
            inherit pname version dependencies;
            src = "${finalAttrs.src}/packages/coding-agent/skills/${directory}";
            pyproject = true;
            build-system = [ python3.pkgs.hatchling ];
          };
        runtime = finalAttrs.passthru.primeAgentRuntime;
      in
      # update.py relies on adjacent directory and version fields to update
      # each bundled skill independently when upstream versions diverge.
      [
        (buildSkill {
          directory = "agent-message";
          version = "0.1.0";
        })
        (buildSkill {
          directory = "agent-observe";
          version = "0.1.0";
        })
        (buildSkill {
          directory = "attach-image";
          version = "0.1.0";
          pname = "prime-agent-skill-attach-image";
          dependencies = with python3.pkgs; [
            pillow
            runtime
          ];
        })
        (buildSkill {
          directory = "compact";
          version = "0.1.0";
        })
        (buildSkill {
          directory = "edit";
          version = "0.1.0";
        })
        (buildSkill {
          directory = "goal";
          version = "0.1.0";
        })
        (buildSkill {
          directory = "linear";
          version = "0.1.0";
          pname = "prime-agent-skill-linear";
          dependencies = with python3.pkgs; [
            httpx
            mcp
            runtime
          ];
        })
        (buildSkill {
          directory = "notion";
          version = "0.1.0";
          pname = "prime-agent-skill-notion";
          dependencies = with python3.pkgs; [
            httpx
            mcp
            runtime
          ];
        })
        (buildSkill {
          directory = "refine";
          version = "0.1.0";
        })
        (buildSkill {
          directory = "rlm-heartbeat";
          version = "0.1.0";
        })
        (buildSkill {
          directory = "websearch";
          version = "0.1.0";
          pname = "prime-agent-skill-websearch";
          dependencies = with python3.pkgs; [
            httpx
            runtime
          ];
        })
      ];

    pythonRuntime = python3.withPackages (
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
