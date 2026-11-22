{ pkgs, perSystem }:
let
  # 1.17.0 fixes `--flake` with Nix 2.35; drop once nixpkgs has it.
  nix-update = pkgs.nix-update.overridePythonAttrs (old: rec {
    version = "1.17.0";
    src = pkgs.fetchFromGitHub {
      owner = "Mic92";
      repo = "nix-update";
      tag = "v${version}";
      hash = "sha256-TCOhUWb53V3nrJRD3JuADly1U9fNi0Z79QMcjhbefHg=";
    };
    build-system = [ pkgs.python3Packages.hatchling ];
    dependencies = (old.dependencies or [ ]) ++ [ pkgs.python3Packages.ast-grep-py ];
  });
in
pkgs.mkShellNoCC {
  packages = [
    # Linter for package definitions (see rules/, sgconfig.yml)
    pkgs.ast-grep

    # Tools needed for update scripts
    pkgs.bash
    pkgs.coreutils
    pkgs.curl
    pkgs.gh
    pkgs.gnugrep
    pkgs.gnused
    pkgs.jq
    pkgs.mypy
    nix-update
    pkgs.nodejs
    pkgs.nushell

    # Formatter
    perSystem.self.formatter
  ]
  # Sandbox for updater code (.github/ci/update.py)
  ++ pkgs.lib.optional pkgs.stdenv.hostPlatform.isLinux pkgs.bubblewrap;

  shellHook = ''
    export PRJ_ROOT=$PWD
  '';
}
