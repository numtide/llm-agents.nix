# openfang - built from source on corepkgs (nixpkgs-free) via mkCargo. Uses
# native-tls -> openssl-sys; openssl = true wires the pinned openssl (headers +
# libs, OPENSSL_NO_VENDOR) so it links our openssl instead of building one from
# source with perl.
{
  mkCargo,
  coreFetchurl,
  flake,
}:
let
  data = builtins.fromJSON (builtins.readFile ./hashes.json);
in
mkCargo {
  pname = "openfang";
  inherit (data) version;
  src = coreFetchurl {
    url = "https://github.com/RightNow-AI/openfang/archive/refs/tags/v${data.version}.tar.gz";
    inherit (data) hash;
  };
  cargoLock = ./Cargo.lock;
  binaries = [ "openfang" ];
  cargoBuildFlags = [
    "--package"
    "openfang-cli"
  ];
  openssl = true;

  category = "AI Coding Agents";
  meta = {
    description = "Open-source Agent OS built in Rust — CLI for the OpenFang platform";
    homepage = "https://github.com/RightNow-AI/openfang";
    changelog = "https://github.com/RightNow-AI/openfang/releases/tag/v${data.version}";
    license = flake.lib.licenses.mit;
    sourceProvenance = [ flake.lib.sourceTypes.fromSource ];
    maintainers = [ flake.lib.maintainers.viniciuspalma ];
  };
}
