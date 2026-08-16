# freebuff (Codebuff's free coding agent) - built on corepkgs, the repo's
# nixpkgs-free packaging system. `mkPackage` (from the flake scope) fetches the
# prebuilt release tarball and wraps it; version + per-platform hashes come from
# the shared ./hashes.json (the same file nix-update bumps), so nothing drifts.
#
# freebuff ships a bun --compile single-file binary in a tarball: on Linux its
# appended JS payload segfaults on any ELF rewrite, so kind = "loader" leaves it
# byte-intact and invokes the pinned glibc loader through the wrapper. It shells
# out to ripgrep, so the pinned rg joins the wrapper PATH.
{
  mkPackage,
  flake,
  corePins,
}:
let
  # system -> {platform} URL token.
  platforms = {
    x86_64-linux = "linux-x64";
    aarch64-linux = "linux-arm64";
    aarch64-darwin = "darwin-arm64";
  };
  urlTemplate = "https://github.com/CodebuffAI/codebuff-community/releases/download/freebuff-v{version}/freebuff-{platform}.tar.gz";
in
mkPackage {
  pname = "freebuff";
  hashesFile = ./hashes.json;
  inherit platforms urlTemplate;
  unpack = "tar";
  binary = "freebuff";
  kind = "loader";

  runtimePkgs = [ corePins.ripgrep ];

  category = "AI Coding Agents";

  meta = {
    description = "The world's strongest free coding agent";
    homepage = "https://freebuff.com";
    changelog = "https://github.com/CodebuffAI/codebuff-community/releases";
    license = flake.lib.licenses.asl20;
    sourceProvenance = [ flake.lib.sourceTypes.binaryNativeCode ];
    maintainers = [ flake.lib.maintainers.ocfox ];
  };
}
