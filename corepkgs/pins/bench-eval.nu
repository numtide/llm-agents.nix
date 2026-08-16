#!/usr/bin/env nix
#! nix shell --inputs-from .# nixpkgs#nushell nixpkgs#hyperfine --command nu

# Compare eval speed of the pins backends (corepkgs/pins/*.nix).
#
# The three nixpkgs-free backends do very different amounts of eval work:
#   closure    - returns bare appendContext path strings (~free, but GC-fragile)
#   store      - returns impure store paths (~free, impure)
#   rehydrated - replays a serialized .drv graph in pure Nix (real cost, durable)
# plus pkgs (full nixpkgs eval) as a reference ceiling.
#
# Each run forces every pin's outPath (or one pin's, in single-pin mode) via
# `nix eval`; hyperfine does the timing (warmup + statistical runs). nix startup
# (~30 ms) and a bare `import` (~90 ms) are a fixed floor - subtract to read the
# marginal eval cost.
#
# Usage:  ./corepkgs/pins/bench-eval.nu [--runs 10] [--warmup 3] [--system x86_64-linux]

const SYSTEM = "x86_64-linux"
# nixpkgs-free backends in ascending eval cost, then pkgs as a reference ceiling.
const BACKENDS = ["store" "closure" "rehydrated" "pkgs"]

# Repo root: this script lives in corepkgs/pins/.
def repo-root []: nothing -> string {
  $env.FILE_PWD | path join .. .. | path expand
}

def nixpkgs-flakeref [root: string]: nothing -> string {
  let rev = (open ($root | path join flake.lock) | from json | get nodes.nixpkgs.locked.rev)
  $"github:NixOS/nixpkgs/($rev)"
}

# Build the nix expression that forces the pins. `pin` empty => force all pins
# (toJSON the whole set); otherwise force just that one pin's outPath. Values are
# already outPath strings for closure/store/rehydrated; derivations for pkgs, so
# normalise with `v.outPath` on the non-string case.
#
# Note: nix expressions are full of literal `(`, which nushell's `$"..."` would
# read as interpolation - so build them with plain-string `+` concatenation.
def backend-expr [backend: string, root: string, np: string, system: string, pin: string]: nothing -> string {
  let provider = if $backend == "pkgs" {
    "import " + $root + "/corepkgs/pins/pkgs.nix (import (builtins.getFlake \"" + $np + "\") { system = \"" + $system + "\"; })"
  } else {
    "import " + $root + "/corepkgs/pins/" + $backend + ".nix \"" + $system + "\""
  }
  if ($pin | is-empty) {
    "let r = (" + $provider + "); in builtins.toJSON (builtins.mapAttrs (_: v: if builtins.isString v then v else v.outPath) r)"
  } else {
    "let v = (" + $provider + ")." + $pin + "; in if builtins.isString v then v else v.outPath"
  }
}

# Run hyperfine, preferring one on PATH (the shebang supplies it) and otherwise
# falling back to `nix run` for when the script is invoked through `nu file.nu`.
def hyperfine-run [args: list<string>]: nothing -> nothing {
  if (which hyperfine | is-not-empty) {
    ^hyperfine ...$args
  } else {
    ^nix run nixpkgs#hyperfine -- ...$args
  }
}

# Bench every backend for one scenario (pin = "" => all pins) with hyperfine,
# then read its JSON export back into a table. Each expr goes to a temp .nix file
# so hyperfine's shell never has to quote the (space/brace/quote-heavy) nix code.
def scenario [title: string, root: string, np: string, system: string, pin: string, runs: int, warmup: int]: nothing -> table {
  let tmp = (mktemp --directory)
  # hyperfine args: per backend, a named command evaluating its expr file.
  mut args = [
    "--warmup" ($warmup | into string)
    "--runs" ($runs | into string)
    "--style" "basic"
    "--export-json" ($tmp | path join out.json)
  ]
  for b in $BACKENDS {
    let file = ($tmp | path join $"($b).nix")
    backend-expr $b $root $np $system $pin | save --force $file
    $args = ($args | append ["-n" $b $"nix eval --impure --raw --file ($file)"])
  }
  print $"\n(ansi green_bold)($title)(ansi reset)"
  hyperfine-run $args
  # hyperfine reports seconds; convert to ms and add a ratio-vs-fastest column.
  let results = (open ($tmp | path join out.json) | get results)
  let fastest = ($results | get mean | math min)
  $results | each {|r|
    {
      backend: $r.command
      mean_ms: ($r.mean * 1000 | math round --precision 1)
      min_ms: ($r.min * 1000 | math round --precision 1)
      max_ms: ($r.max * 1000 | math round --precision 1)
      vs_fastest: $"($r.mean / $fastest | math round --precision 1)x"
    }
  }
}

def main [--runs: int = 10, --warmup: int = 3, --system: string = $SYSTEM] {
  let root = (repo-root)
  let np = (nixpkgs-flakeref $root)
  print $"pins eval benchmark  ·  system=($system)  ·  runs=($runs)  warmup=($warmup)"
  print $"repo=($root)"
  scenario "Force ALL pins" $root $np $system "" $runs $warmup | print
  scenario "Force ONE pin (glibc)" $root $np $system "glibc" $runs $warmup | print
  print $"\n(ansi grey)Floor: nix startup ~30ms, bare import ~90ms - subtract for marginal eval cost.(ansi reset)"
}
