# The bootstrap seed, zero nixpkgs:
#   busybox - truly-static; archive extraction (tar/unzip/xz) nushell lacks.
#   nu      - nushell (truly-static musl), the build-script runtime. The tiny sh
#             bootstrap (mk/drv-sh) untars it, since nu can't extract itself.
# Trusted prebuilt static binaries. Keep small + swappable (future: GNU Mes seed).
scope:
let
  inherit (scope)
    system
    fetchurl
    mkDrvSh
    systems
    ;
  sys = systems.${system};
  isDarwin = builtins.match ".*-darwin" system != null;

  # Darwin has no static busybox; it uses the system toolchain in the sandbox.
  busybox =
    if isDarwin then
      null
    else
      fetchurl {
        inherit (sys.busybox) url hash;
        executable = true;
      };
  nuTar = fetchurl { inherit (sys.nu) url hash; };
  nushell = mkDrvSh {
    name = "nushell";
    env = { inherit nuTar; };
    script = ''
      mkdir -p "$out/bin"
      tar -xzf "$nuTar"
      cp "${sys.nu.dir}/nu" "$out/bin/nu"
      chmod 0755 "$out/bin/nu"
    '';
  };
in
{
  inherit busybox;
  nu = "${nushell}/bin/nu";
}
