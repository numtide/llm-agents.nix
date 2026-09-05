# nixbot effects. mkEffect is inlined to avoid a nixbot flake input.
{ pkgs, site }:
let
  inherit (pkgs) lib;

  mkEffect =
    {
      name,
      effectScript,
      inputs ? [ ],
      # Pushable clone at $NIXBOT_EFFECT_CHECKOUT, see nixbot docs/EFFECTS.md.
      checkout ? false,
    }:
    pkgs.stdenvNoCC.mkDerivation {
      inherit name effectScript;
      isEffect = true;
      __nixbot_effect_checkout = checkout;
      __hci_effect_fsroot_copy = pkgs.runCommand "effect-root" { } ''
        mkdir -p $out/bin $out/usr/bin
        ln -s ${lib.getExe pkgs.bash} $out/bin/sh
        ln -s ${pkgs.coreutils}/bin/env $out/usr/bin/env
      '';
      secretsMap = builtins.toJSON { };
      nativeBuildInputs = [ pkgs.cacert ] ++ inputs;
      phases = [
        "initPhase"
        "effectPhase"
      ];
      initPhase = ''
        exec </dev/null
        export HOME=/build/home
        mkdir -p "$HOME"
      '';
      effectPhase = ''eval "$effectScript"'';
    };

  # Keep eval/build of the effect closure green on non-main branches.
  runIf =
    condition: effect:
    if condition then
      { run = effect; }
    else
      {
        dependencies = effect.inputDerivation // {
          isEffect = false;
          buildDependenciesOnly = true;
        };
      };
in
{ primaryRepo, ... }:
{
  onPush.default.outputs.effects.gh-pages = runIf ((primaryRepo.branch or null) == "main") (mkEffect {
    name = "gh-pages";
    checkout = true;
    inputs = [ pkgs.git ];
    effectScript = ''
      cd "$NIXBOT_EFFECT_CHECKOUT"
      git config user.email "nixbot@numtide.com"
      git config user.name "nixbot"
      # History of generated files is not worth keeping.
      git checkout -q --orphan gh-pages
      git rm -rfq .
      cp -r --no-preserve=mode,ownership ${site}/. .
      git add -A
      git commit -q -m "Deploy site for ${primaryRepo.rev}"
      git push -f origin gh-pages
    '';
  });
}
