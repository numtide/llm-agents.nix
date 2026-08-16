# vix - built from source on corepkgs (nixpkgs-free) via mkGo. cgo = true: the
# tree-sitter go bindings compile bundled grammar C via zig cc (no external C
# lib); the output is dynamic, patchelf'd to the pinned glibc. In-tree vendor/.
{
  mkGo,
  coreFetchurl,
  flake,
}:
let
  data = builtins.fromJSON (builtins.readFile ./hashes.json);
in
mkGo {
  pname = "vix";
  inherit (data) version;
  src = coreFetchurl {
    url = "https://github.com/get-vix/vix/archive/refs/tags/v${data.version}.tar.gz";
    inherit (data) hash;
  };
  cgo = true;
  subPackages = [
    "cmd/vix"
    "cmd/vixd"
  ];
  binaries = [
    "vix"
    "vixd"
  ];
  ldflags = [
    "-s"
    "-w"
    "-X main.Version=${data.version}"
  ];
  category = "AI Coding Agents";
  meta = {
    description = "Sleek, Fast and Token Efficient AI Coding Agent";
    homepage = "https://github.com/get-vix/vix";
    changelog = "https://github.com/get-vix/vix/releases/tag/v${data.version}";
    license = flake.lib.licenses.agpl3Only;
    sourceProvenance = [ flake.lib.sourceTypes.fromSource ];
    maintainers = [ flake.lib.maintainers.daspk04 ];
  };
}
