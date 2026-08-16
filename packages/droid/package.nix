# droid (Factory AI's CLI) - built on corepkgs, the repo's nixpkgs-free
# packaging system. droid is a bun --compile single-file binary that bundles its
# own ripgrep for code search.
#
# kind = "loader": a bun-compiled binary segfaults on any ELF rewrite (its
# appended JS payload), so leave it byte-intact and invoke the pinned glibc
# loader through the wrapper. rg is fetched separately and bundled onto PATH.
#
# version + the droid/ripgrep per-platform hashes live in ./hashes.json (nested
# per binary, so mkPackage's shared-hashes reader can't consume it; we read it in
# a let-block instead). x86_64 only for now.
{
  mkPackage,
  coreFetchurl,
  flake,
}:
let
  data = builtins.fromJSON (builtins.readFile ./hashes.json);
in
mkPackage {
  pname = "droid";
  inherit (data) version;
  src = coreFetchurl {
    url = "https://downloads.factory.ai/factory-cli/releases/${data.version}/linux/x64/droid";
    hash = data.droid.x86_64-linux;
  };
  unpack = "none";
  kind = "loader";
  runtimeBins = [
    {
      name = "rg";
      src = coreFetchurl {
        url = "https://downloads.factory.ai/ripgrep/linux/x64/rg";
        hash = data.ripgrep.x86_64-linux;
      };
    }
  ];

  category = "AI Coding Agents";

  meta = {
    description = "Factory AI's Droid - AI-powered development agent for your terminal";
    platforms = [ "x86_64-linux" ];
    homepage = "https://factory.ai";
    changelog = "https://docs.factory.ai/changelog/cli-updates";
    downloadPage = "https://factory.ai/product/ide";
    license = flake.lib.licenses.unfree;
    sourceProvenance = [ flake.lib.sourceTypes.binaryNativeCode ];
    maintainers = [ ];
  };
}
