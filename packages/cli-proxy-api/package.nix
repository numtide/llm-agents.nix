# cli-proxy-api - built from source on corepkgs (nixpkgs-free) via mkGo.
# CGO_ENABLED=0, so the output is a fully static binary (no glibc, no patchelf).
# Modules are vendored by a single vendorHash FOD.
{
  mkGo,
  coreFetchurl,
  flake,
}:
let
  data = builtins.fromJSON (builtins.readFile ./hashes.json);
in
mkGo {
  pname = "cli-proxy-api";
  inherit (data) version;
  src = coreFetchurl {
    url = "https://github.com/router-for-me/CLIProxyAPI/archive/refs/tags/v${data.version}.tar.gz";
    inherit (data) hash;
  };
  vendorHash = data.vendorHash;
  subPackages = [ "cmd/server" ];
  binaries = [ "cli-proxy-api" ];
  ldflags = [
    "-s"
    "-w"
    "-X main.Version=${data.version}"
    "-X main.Commit=nixpkgs"
    "-X main.BuildDate=1970-01-01T00:00:00Z"
  ];

  category = "Utilities";
  meta = {
    description = "Unified proxy providing OpenAI/Gemini/Claude/Codex compatible APIs for AI coding CLI tools";
    homepage = "https://github.com/router-for-me/CLIProxyAPI";
    changelog = "https://github.com/router-for-me/CLIProxyAPI/releases";
    license = flake.lib.licenses.mit;
    sourceProvenance = [ flake.lib.sourceTypes.fromSource ];
    maintainers = [ flake.lib.maintainers.odysseus0 ];
  };
}
