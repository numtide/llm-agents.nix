{ pkgs, flake }:
pkgs.runCommand "workbuddy-updater-tests"
  {
    nativeBuildInputs = [ pkgs.python3 ];
  }
  ''
    export PYTHONDONTWRITEBYTECODE=1
    PYTHONPATH=${flake}/scripts python3 -m unittest discover \
      -s ${flake}/packages/workbuddy -p '*_test.py' -v
    touch $out
  ''
