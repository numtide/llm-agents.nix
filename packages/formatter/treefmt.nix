{
  pkgs,
  lib,
  shuck,
  ...
}:
let
  mypy-check = pkgs.writeShellApplication {
    name = "mypy-check";
    runtimeInputs = [
      pkgs.mypy
      pkgs.findutils
      pkgs.python3Packages.pyelftools
    ];
    text = builtins.readFile ./../../scripts/check.sh;
  };

  # Like writeShellApplication, but for Nushell: nu shebang, runtimeInputs on
  # PATH, build-time nu-check parse validation.
  writeNushellApplication =
    {
      name,
      text,
      runtimeInputs ? [ ],
    }:
    pkgs.writeTextFile {
      inherit name;
      executable = true;
      destination = "/bin/${name}";
      text = ''
        #!${lib.getExe pkgs.nushell}
      ''
      + lib.optionalString (runtimeInputs != [ ]) ''
        $env.PATH = ("${lib.makeBinPath runtimeInputs}" | split row (char esep) | append $env.PATH)
      ''
      + "\n"
      + text;
      checkPhase = ''
        ${lib.getExe pkgs.nushell} --no-config-file --commands "nu-check --debug $target | ignore"
      '';
    };

  # Must not be named "nu-check": that would shadow the nushell builtin the
  # script itself calls.
  nu-parse-check = writeNushellApplication {
    name = "nu-parse-check";
    text = builtins.readFile ./../../scripts/treefmt-nu-check.nu;
  };
in
{
  package = pkgs.treefmt;

  projectRootFile = "flake.lock";

  # Inlined pin sources (nixpkgs patches/hooks) for the rehydrated pins backend.
  # They are re-added by content via builtins.path, so their bytes are hashed
  # into the store path - any reformat (many are *.sh) would break rehydration.
  # Keep them verbatim; never let a formatter touch them.
  settings.global.excludes = [ "corepkgs/pins/rehydrated/srcs/**" ];

  programs.deadnix.enable = true;
  programs.nixfmt.enable = true;

  programs.mdformat.enable = true;

  # Shell: trialling shuck (Rust) instead of shellcheck (Haskell) + shfmt (Go).
  # shuck format is behind SHUCK_EXPERIMENTAL, so wrap it to set that env.
  # shuck check is the linter (exits non-zero on violations); it honors
  # ShellCheck-compatible `# shellcheck disable=SCxxxx` directives.
  programs.taplo.enable = true;
  programs.yamlfmt.enable = true;

  # Python formatting and linting
  programs.ruff-format.enable = true;
  programs.ruff-check.enable = true;

  settings.formatter.deadnix.pipeline = "nix";
  settings.formatter.deadnix.priority = 1;
  settings.formatter.nixfmt.pipeline = "nix";
  settings.formatter.nixfmt.priority = 2;

  # shuck format (whitespace/layout) then shuck check (lint) on the same files.
  settings.formatter.shuck-format = {
    command = lib.getExe (
      pkgs.writeShellScriptBin "shuck-format" ''
        export SHUCK_EXPERIMENTAL=1
        # --dialect bash: our sourced setup-hooks use `[[ ]]` + `# shellcheck
        # shell=bash` (no shebang); shuck ignores that directive and would parse
        # them as POSIX and fail. bash is a superset, so formatting the POSIX
        # builders as bash is byte-identical. --indent-width 2 matches shfmt.
        exec ${lib.getExe shuck} format --dialect bash --indent-style space --indent-width 2 "$@"
      ''
    );
    includes = [ "*.sh" ];
    pipeline = "shell";
    priority = 1;
  };
  settings.formatter.shuck-check = {
    command = lib.getExe shuck;
    options = [ "check" ];
    includes = [ "*.sh" ];
    pipeline = "shell";
    priority = 2;
  };

  settings.formatter.ruff-check.pipeline = "python";
  settings.formatter.ruff-check.priority = 1;
  settings.formatter.ruff-format.pipeline = "python";
  settings.formatter.ruff-format.priority = 2;

  # ast-grep lint rules (../../rules via sgconfig.yml at project root) for
  # anti-patterns Nix evaluation won't reject; check-only, no rewrites.
  settings.formatter.ast-grep-check = {
    command = lib.getExe pkgs.ast-grep;
    options = [
      "scan"
      "--error"
    ];
    includes = [
      "*.nix"
      "*.py"
    ];
  };

  # Custom mypy check that handles our update.py scripts correctly
  settings.formatter.mypy-check = {
    command = "${mypy-check}/bin/mypy-check";
    includes = [ "*.py" ];
    pipeline = "python";
    priority = 3;
  };

  # Nushell has no mature formatter yet, so parse-check only
  settings.formatter.nu-check = {
    command = "${nu-parse-check}/bin/nu-parse-check";
    includes = [ "*.nu" ];
  };
}
