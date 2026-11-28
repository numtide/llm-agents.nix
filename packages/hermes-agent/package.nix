{
  mkUpdater,
  lib,
  stdenv,
  callPackage,
  runCommand,
  makeWrapper,
  hermes-agent-unwrapped ? callPackage ./unwrapped.nix { },
  extras ? null,
  extraPythonPackages ? _: [ ],
}:

let
  defaultExtras = [
    "anthropic"
    "mistral"
    "bedrock"
    "mcp"
    "acp"
    "exa"
    "firecrawl"
    "parallel-web"
    "ddgs"
    "fal"
    "edge-tts"
    "tts-premium"
    "voice"
    "messaging"
    "matrix"
    "modal"
  ];

  # Adapters swallow ImportError (#4175); acp_adapter needs the pre-0.11 ACP schema (#7650).
  importChecks = {
    acp = [ "acp_adapter.server" ];
    messaging = [
      "slack_bolt"
      "discord"
      "telegram.ext"
    ];
  }
  // lib.optionalAttrs stdenv.hostPlatform.isLinux {
    matrix = [
      "mautrix.crypto"
      "asyncpg"
      "aiosqlite"
    ];
  };

  entryPoints = {
    hermes = "hermes_cli.main";
    hermes-agent = "agent.legacy_cli";
    hermes-acp = "acp_adapter.entry";
  };

  mkHermes = lib.makeOverridable (
    {
      hermes-agent-unwrapped,
      extras,
      extraPythonPackages,
    }:
    let
      unwrapped = hermes-agent-unwrapped;
      inherit (unwrapped) version optional-dependencies python;
      sitePackages = "${unwrapped}/${python.sitePackages}";
      useUnwrapped =
        attr: _:
        throw "hermes-agent only wraps Hermes; override hermes-agent-unwrapped = hermes-agent.unwrapped.${attr} ... instead";
      unknown = lib.subtractLists (lib.attrNames optional-dependencies) extras;
      env = python.withPackages (
        ps:
        unwrapped.dependencies
        ++ lib.concatMap (name: optional-dependencies.${name}) extras
        ++ extraPythonPackages ps
      );
      imports = lib.concatMap (name: importChecks.${name} or [ ]) extras;
      # Like .hermes-wrapped, but argv[0] names this wrapper so relaunches keep the environment.
      entryScript = name: module: ''
        cat > $out/libexec/hermes-agent/${name} <<EOF
        #!${env}/bin/python3
        import site
        import sys
        site.addsitedir("${sitePackages}")
        sys.argv[0] = "$out/bin/${name}"
        from ${module} import main
        sys.exit(main())
        EOF
        chmod +x $out/libexec/hermes-agent/${name}
        makeWrapper $out/libexec/hermes-agent/${name} $out/bin/${name} \
          ${lib.escapeShellArgs (
            unwrapped.wrapperArgs {
              out = unwrapped;
              inherit env;
            }
          )}
      '';
    in
    assert lib.assertMsg (unknown == [ ])
      "hermes-agent: unknown extras: ${toString unknown}; available: ${toString (lib.attrNames optional-dependencies)}";
    runCommand "hermes-agent-${version}"
      {
        nativeBuildInputs = [ makeWrapper ];
        passthru = unwrapped.passthru // {
          inherit
            version
            extras
            defaultExtras
            unwrapped
            ;
          inherit (unwrapped) src;
          pythonEnv = env;
          updater = mkUpdater { kind = "script"; };
          withPythonPackages =
            f:
            mkHermes {
              inherit hermes-agent-unwrapped extras;
              extraPythonPackages = ps: extraPythonPackages ps ++ f ps;
            };
          overrideAttrs = useUnwrapped "overrideAttrs";
          overridePythonAttrs = useUnwrapped "overridePythonAttrs";
        };
        inherit (unwrapped) meta;
      }
      ''
        mkdir -p $out/bin $out/libexec/hermes-agent
        ${lib.concatStrings (lib.mapAttrsToList entryScript entryPoints)}
        ln -s ${unwrapped}/share $out/share

        ${python.interpreter} - ${lib.escapeShellArgs (lib.attrNames optional-dependencies)} <<'EOF'
        import sys
        import tomllib
        with open("${unwrapped.src}/pyproject.toml", "rb") as f:
            upstream = tomllib.load(f)["project"]["optional-dependencies"]
        stale = [name for name in sys.argv[1:] if name not in upstream]
        if stale:
            sys.exit(f"extras no longer upstream: {stale}")
        EOF
        ${lib.optionalString (imports != [ ]) ''
          PYTHONPATH=${sitePackages} ${env}/bin/python3 -c ${lib.escapeShellArg "import ${lib.concatStringsSep ", " imports}"}
        ''}
        HOME=$TMPDIR $out/bin/hermes --version | grep -F ${version}
      ''
  );
in
mkHermes {
  inherit hermes-agent-unwrapped extraPythonPackages;
  extras = if extras == null then defaultExtras else extras;
}
