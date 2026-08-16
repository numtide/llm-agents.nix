# Prove lib/interpolate.nix and scripts/updater/interpolate.py agree; if they
# diverge, build and updater fetch different URLs. Runs both over one shared
# fixture and fails unless Nix == Python == expected for every case.
{
  pkgs,
  flake,
  interpolate, # corepkgs' interpolate, from core.lib (the file this check proves)
}:
let
  casesJson = builtins.readFile ../scripts/updater/interpolate_cases.json;
  cases = builtins.fromJSON casesJson;
  nixResults = map (case: interpolate case.template case.vars) cases;
in
pkgs.runCommand "interpolate-conformance"
  {
    nativeBuildInputs = [ pkgs.python3 ];
    nixResultsJson = builtins.toJSON nixResults;
    inherit casesJson;
  }
  ''
    cp -r ${flake}/scripts scripts
    export PYTHONPATH="$PWD/scripts"
    printf '%s' "$casesJson" > cases.json
    printf '%s' "$nixResultsJson" > nix.json
    python3 - <<'PY'
    import json
    from pathlib import Path
    from updater.interpolate import interpolate

    cases = json.loads(Path("cases.json").read_text())
    nix = json.loads(Path("nix.json").read_text())
    for case, nix_out in zip(cases, nix, strict=True):
        py_out = interpolate(case["template"], case["vars"])
        if not (py_out == nix_out == case["expected"]):
            msg = (
                f"interpolate divergence in case {case['name']!r}:\n"
                f"  template = {case['template']!r}\n"
                f"  vars     = {case['vars']}\n"
                f"  nix      = {nix_out!r}\n"
                f"  python   = {py_out!r}\n"
                f"  expected = {case['expected']!r}"
            )
            raise SystemExit(msg)
    print(f"{len(cases)} cases: Nix interpolate == Python interpolate == expected")
    PY
    touch $out
  ''
