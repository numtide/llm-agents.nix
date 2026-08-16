{
  flake,
  inputs,
  pkgs,
  nixfmt-rs,
  shuck,
}:
# treefmt with config
let
  formatter = inputs."treefmt-nix".lib.mkWrapper pkgs {
    _file = __curPos.file;
    imports = [ ./treefmt.nix ];
    # dogfood: format Nix with corepkgs' own from-source build of nixfmt-rs (the
    # Rust port of nixfmt), byte-identical to nixpkgs' nixfmt.
    programs.nixfmt.package = nixfmt-rs;
    # trial: shuck (Rust) as the shell linter+formatter, replacing shellcheck+shfmt.
    _module.args.shuck = shuck;
  };

  check =
    pkgs.runCommand "format-check"
      {
        nativeBuildInputs = [
          formatter
          pkgs.git
        ];
      }
      ''
        export HOME=$NIX_BUILD_TOP/home

        # keep timestamps so that treefmt is able to detect mtime changes
        cp --preserve=mode,timestamps -r ${flake} source
        cd source
        chmod -R u+w .
        git init --quiet
        git add .
        treefmt --no-cache
        if ! git diff --exit-code; then
          echo "-------------------------------"
          echo "aborting due to above changes ^"
          exit 1
        fi
        touch $out
      '';
in
formatter
// {
  passthru = formatter.passthru // {
    hideFromDocs = true;
    tests = {
      check = check;
    };
  };
}
