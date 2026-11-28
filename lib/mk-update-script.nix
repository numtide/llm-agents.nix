# Generate a nixpkgs-standard `passthru.updateScript` from a validated
# `passthru.updater` config. The script carries its own tools so nothing about
# the update lives in CI; it runs scripts/updater/run.py against the config, or
# the package's own update.py for kind "script".
{
  lib,
  writeShellApplication,
  python3,
  nix,
  git,
  cacert,
  bun,
  nodejs,
}:
{
  name,
  config,
}:
let
  # Tools a kind's flow shells out to, on top of the common set.
  extraToolsByKind = {
    "npm" = [ nodejs ];
    "bun-github" = [
      bun
      git
    ];
  };
  isScript = config.kind == "script";
  extraTools = if isScript then config.tools or [ ] else extraToolsByKind.${config.kind} or [ ];
  # The flakeAttr is just `.#<name>`, so inject it instead of restating it in
  # every config.
  needsFlakeAttr = builtins.elem config.kind [
    "github-source"
    "npm"
  ];
  resolvedConfig = if needsFlakeAttr then config // { flakeAttr = ".#${name}"; } else config;
  configJson = builtins.toJSON resolvedConfig;
in
writeShellApplication {
  name = "update-${name}";
  runtimeInputs = [
    python3
    nix
    git
    cacert
  ]
  ++ extraTools;
  text = ''
    # Run from the flake root (nix run / update.nix both preserve cwd there).
    export SSL_CERT_FILE="${cacert}/etc/ssl/certs/ca-bundle.crt"
    export PYTHONPATH="$PWD/scripts''${PYTHONPATH:+:$PYTHONPATH}"
    ${
      if isScript then
        ''
          exec python3 ${lib.escapeShellArg "packages/${name}/update.py"} "$@"
        ''
      else
        ''
          exec python3 -m updater.run \
            --pkg-dir ${lib.escapeShellArg "packages/${name}"} \
            --config ${lib.escapeShellArg configJson}
        ''
    }
  '';
}
