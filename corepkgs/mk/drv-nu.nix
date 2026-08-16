# mkDrvNu: a nixpkgs-free, stdenv-free derivation. Builder is a static nushell;
# __structuredAttrs exposes the attrs as JSON that nushell `open`s natively, so
# params pass as real lists/records instead of string-munged env vars.
# Prelude binds `$attrs` and puts busybox archive tools on PATH (nushell has no
# built-in tar/unzip/xz).
scope:
{
  name,
  script, # inline nushell string, OR a path to a .nu file (readFile'd)
  env ? { },
}:
let
  inherit (scope) system seed;
  scriptText = if builtins.isPath script then builtins.readFile script else script;
  isDarwin = builtins.match ".*-darwin" system != null;
  # Darwin has no static busybox; use the sandbox's system tools (/usr/bin, /bin)
  # like nixpkgs' darwin stdenv. nushell has mkdir/cp/ln/mv built-in; only
  # tar/unzip/chmod need externals.
  prelude =
    if isDarwin then
      ''
        let attrs = (open $env.NIX_ATTRS_JSON_FILE)
        let out = $attrs.outputs.out
        $env.PATH = ["/usr/bin" "/bin"]
      ''
    else
      ''
        let attrs = (open $env.NIX_ATTRS_JSON_FILE)
        let out = $attrs.outputs.out
        # busybox dispatches on argv[0]: copy it to a "busybox"-named path,
        # --install its applets, put them on PATH.
        let bbdir = $"($env.NIX_BUILD_TOP)/.bb"
        mkdir $bbdir
        cp @busybox@ $"($bbdir)/busybox"
        ^$"($bbdir)/busybox" --install -s $bbdir
        $env.PATH = ($env.PATH | prepend $bbdir)
      '';
in
derivation (
  env
  // {
    inherit name system;
    __structuredAttrs = true;
    builder = seed.nu;
    args = [
      "--no-config-file"
      "--commands"
      (builtins.replaceStrings [ "@busybox@" ] [ (if isDarwin then "" else "${seed.busybox}") ] (
        prelude + "\n" + scriptText
      ))
    ];
  }
)
