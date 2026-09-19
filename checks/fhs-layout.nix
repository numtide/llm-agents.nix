# Enforce an FHS-like root for every package output.
#
# Whatever a package puts directly under $out also lands in the top level of
# every profile assembled with pkgs.buildEnv or home-manager's
# home.packages.  Two packages shipping the same root file name -- an
# index.js, a node, an rg -- then collide and the profile fails to build
# (#9364).  Restricting the root to the usual FHS directories keeps the
# per-package payload one level down, where only the package itself looks.
#
# Every attribute of flake.packages.<system> is covered, including the ones
# carrying passthru.hideFromDocs: a profile collision does not care whether a
# package is listed in the README.
{
  pkgs,
  flake,
  system,
  ...
}:

let
  inherit (pkgs) lib;

  # The only entries allowed directly under $out.
  allowedRootEntries = [
    "Applications"
    "bin"
    "etc"
    "include"
    "lib"
    "lib64"
    "libexec"
    "nix-support"
    "opt"
    "sbin"
    "share"
  ];

  # Packages whose launcher hardcodes its own root and that therefore cannot
  # be relocated.  Value is the reason, shown when listing the exemptions.
  # Keep this empty unless there is no way to make the package work.
  exceptions = { };

  packages = flake.packages.${system} or { };
  checked = removeAttrs packages (builtins.attrNames exceptions);
in
pkgs.runCommand "fhs-layout"
  {
    allowed = lib.concatStringsSep "\n" allowedRootEntries;
    # "<name>\t<store path>" per line, each line terminated so that read sees
    # the last one as well.  Interpolating the outputs is what makes every
    # package an input of this derivation.
    manifest = lib.concatMapStrings (line: line + "\n") (
      lib.mapAttrsToList (name: pkg: "${name}\t${pkg}") checked
    );
    # Cross-check against the number of lines the loop actually reads, so a
    # manifest the shell truncates cannot pass the check silently.
    expected = toString (builtins.length (builtins.attrNames checked));
    passAsFile = [
      "allowed"
      "manifest"
    ];
  }
  ''
    status=0
    seen=0

    while IFS="$(printf '\t')" read -r name path; do
      [ -n "$name" ] || continue
      seen=$((seen + 1))

      if [ ! -d "$path" ]; then
        echo "$name: output is not a directory: $path"
        status=1
        continue
      fi

      strays=$(ls -A "$path" | grep -vxF -f "$allowedPath" || true)
      if [ -n "$strays" ]; then
        echo "$name: $path"
        echo "$strays" | sed 's/^/  /'
        status=1
      fi
    done < "$manifestPath"

    if [ "$seen" -ne "$expected" ]; then
      echo "inspected $seen package roots, expected $expected"
      exit 1
    fi

    if [ "$status" -ne 0 ]; then
      echo
      echo "The package roots above carry entries outside the allowlist:"
      sed 's/^/  /' "$allowedPath"
      echo
      echo "Move the payload under \$out/share/<pname> (data, JS bundles, app"
      echo "trees) or \$out/lib/<pname> (native libraries next to a binary) and"
      echo "point \$out/bin/<mainProgram> at it with a symlink or a makeWrapper"
      echo "wrapper. See the Output layout section in AGENTS.md."
      exit 1
    fi

    echo "All package roots are FHS-like"
    touch $out
  ''
