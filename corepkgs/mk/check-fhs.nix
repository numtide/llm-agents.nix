# checkFhs: assert an output is store-only - every ELF's interpreter and NEEDED
# libs resolve inside /nix/store, nothing left on a host loader. Reads the
# constructor's package.fhs: kind = patchelf (resolve via rpath) or loader
# (interpreter is meant to be non-store), libpath, ignoreMissing SONAMEs. nushell.
scope:
{
  package,
  name,
}:
let
  inherit (scope) mkDrvNu pins;
in
mkDrvNu {
  name = "${name}-fhs-check";
  env = {
    inherit package;
    formatelf = "${pins.formatelf}/bin/formatelf";
    kind = package.fhs.kind or "patchelf";
    libpath = package.fhs.libpath or "";
    ignoreMissing = package.fhs.ignoreMissing or "";
  };
  script = ''
    let pkg = $attrs.package
    let fe = $attrs.formatelf
    let kind = $attrs.kind
    let libpath = $attrs.libpath
    let ignore = ($attrs.ignoreMissing | split row " " | where {|x| $x != "" })

    mut fail = false

    # $out folder structure must be FHS-conventional: only hier(7)-style
    # top-level entries, no files dumped at the output root.
    let allowedTop = ["bin" "sbin" "lib" "lib64" "libexec" "share" "include" "etc" "var" "opt" "nix-support"]
    for entry in (^ls -1 $pkg | lines) {
      if not ($entry in $allowedTop) {
        print $"non-FHS $out top-level entry: ($entry)"
        $fail = true
      }
    }

    for f in (^find -L $pkg -type f | lines) {
      let magic = ((^head -c4 $f | ^od -An -tx1) | str replace --all --regex '[^0-9a-f]' "")
      if $magic != "7f454c46" { continue }

      # $ORIGIN = the ELF's own dir (a store path); expand it so a manylinux
      # wheel's $ORIGIN-relative RPATH into its bundled *.libs/ counts as store-only.
      let origin = ($f | path dirname)
      let rpath = (do { ^$fe --print-rpath $f } | complete | get stdout | str trim | str replace --all '$ORIGIN' $origin)
      let search = ((if ($libpath | is-empty) { $rpath } else { $"($rpath):($libpath)" }) | split row ":" | where {|x| $x != "" })

      let interp = (do { ^$fe --print-interpreter $f } | complete | get stdout | str trim)
      if ($interp != "") and (not ($interp | str starts-with "/nix/store/")) {
        if $kind != "loader" {
          print $"FHS interpreter: ($f) -> ($interp)"
          $fail = true
        }
      }

      for d in $search {
        if not ($d | str starts-with "/nix/store/") {
          print $"FHS lib dir: ($f) -> ($d)"
          $fail = true
        }
      }

      for lib in (do { ^$fe --print-needed $f } | complete | get stdout | lines) {
        if ($lib | str starts-with "ld-linux") { continue }
        if ($lib in $ignore) { continue }
        let found = ($search | any {|d| ($"($d)/($lib)" | path exists) })
        if not $found {
          print $"unresolved NEEDED: ($f) needs ($lib)"
          $fail = true
        }
      }
    }

    if $fail {
      print $"FHS check FAILED: ($pkg) still depends on the FHS"
      exit 1
    }
    $"OK: ($pkg) is store-only; every ELF resolves within /nix/store" | save --raw $out
  '';
}
