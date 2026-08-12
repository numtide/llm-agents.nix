{ pkgs, ... }:
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

  quote-flake-inputs = pkgs.writeShellApplication {
    name = "quote-flake-inputs";
    runtimeInputs = [ pkgs.python3 ];
    text = ''
      python3 ${./../../scripts/quote-flake-inputs.py} "$@"
    '';
  };
in
{
  package = pkgs.treefmt;

  projectRootFile = "flake.lock";

  programs.deadnix.enable = true;
  programs.nixfmt.enable = true;

  programs.mdformat.enable = true;

  programs.shellcheck.enable = true;
  programs.shfmt.enable = true;

  programs.taplo.enable = true;
  programs.yamlfmt.enable = true;

  # Python formatting and linting
  programs.ruff-format.enable = true;
  programs.ruff-check.enable = true;

  # zimbatm's law: the attribute after `inputs.` must be quoted.
  settings.formatter.quote-flake-inputs = {
    command = "${quote-flake-inputs}/bin/quote-flake-inputs";
    includes = [ "*.nix" ];
    pipeline = "nix";
    priority = 0;
  };

  settings.formatter.deadnix.pipeline = "nix";
  settings.formatter.deadnix.priority = 1;
  settings.formatter.nixfmt.pipeline = "nix";
  settings.formatter.nixfmt.priority = 2;

  settings.formatter.shellcheck.pipeline = "shell";
  settings.formatter.shellcheck.priority = 1;
  settings.formatter.shfmt.pipeline = "shell";
  settings.formatter.shfmt.priority = 2;

  settings.formatter.ruff-check.pipeline = "python";
  settings.formatter.ruff-check.priority = 1;
  settings.formatter.ruff-format.pipeline = "python";
  settings.formatter.ruff-format.priority = 2;

  # Custom mypy check that handles our update.py scripts correctly
  settings.formatter.mypy-check = {
    command = "${mypy-check}/bin/mypy-check";
    includes = [ "*.py" ];
    pipeline = "python";
    priority = 3;
  };
}
