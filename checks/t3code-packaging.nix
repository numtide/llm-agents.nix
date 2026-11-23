{
  pkgs,
  flake,
  system,
  ...
}:

let
  packages = flake.packages.${system};
  t3code = packages.t3code;
  desktop = packages.t3code-desktop;
  t3codeWithoutProviders = t3code.override { providerPackages = [ ]; };
in
assert t3code.meta.mainProgram == "t3";
assert desktop.meta.mainProgram == "t3code-desktop";
assert !(desktop ? version);
assert t3code.passthru ? resourceMonitor;
assert t3code.passthru ? hyprlandSnapShot;
assert t3code.passthru ? kdeSnapShot;
assert t3code.unwrapped ? override;
assert t3code.pnpmDeps == t3code.unwrapped.pnpmDeps;
assert t3code.unwrapped.drvPath == t3codeWithoutProviders.unwrapped.drvPath;
assert t3code.drvPath != t3codeWithoutProviders.drvPath;
assert t3code.desktop.drvPath != t3codeWithoutProviders.desktop.drvPath;
assert pkgs.lib.hasInfix "package.json').dependencies.electron" (
  builtins.readFile ../packages/t3code/unwrapped.nix
);
assert
  map pkgs.lib.getName t3code.passthru.providerPackages == [
    "codex"
    "claude-code"
    "cursor-agent"
    "grok"
    "opencode"
  ];
pkgs.runCommand "t3code-packaging-check" { } ''
  touch $out
''
