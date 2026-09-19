{
  inputs,
  pkgs,
}:
# A derivation that references all flake inputs to ensure they get cached.
# The reference list goes under nix-support/ so the output is an FHS-like
# directory rather than a bare file (see checks/fhs-layout.nix).
pkgs.runCommand "flake-inputs" { } ''
  mkdir -p $out/nix-support
  echo ${pkgs.lib.concatMapStringsSep " " (name: inputs.${name}) (builtins.attrNames inputs)} \
    > $out/nix-support/flake-inputs
''
// {
  passthru.hideFromDocs = true;
}
