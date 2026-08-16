# Nix mirror of Python's str.format for `{name}` placeholders (unknown ones stay
# as-is). Must stay in lockstep with scripts/updater/interpolate.py.
_scope: template: vars:
builtins.replaceStrings (map (name: "{${name}}") (
  builtins.attrNames vars
)) (builtins.attrValues vars) template
