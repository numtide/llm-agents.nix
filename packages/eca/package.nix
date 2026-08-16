# eca (Editor Code Assistant) - built on corepkgs, the repo's nixpkgs-free
# packaging system. `mkPackage` (from the flake scope) fetches the prebuilt
# native GraalVM artifact and wraps it; version + per-platform hashes come from
# the shared ./hashes.json (the same file nix-update bumps), so nothing drifts.
#
# eca ships a normal dynamic ELF (kind = "patchelf"): the interpreter/rpath are
# rewritten to the pinned glibc plus zlib, which the native image links.
{
  mkPackage,
  corePins,
  flake,
}:
let
  # system -> {platform} URL token, shared by every native release asset.
  platforms = {
    x86_64-linux = "linux-amd64";
    aarch64-linux = "linux-aarch64";
    aarch64-darwin = "macos-aarch64";
  };
  urlTemplate = "https://github.com/editor-code-assistant/eca/releases/download/{version}/eca-native-{platform}.zip";
in
mkPackage {
  pname = "eca";
  hashesFile = ./hashes.json;
  inherit platforms urlTemplate;
  unpack = "zip";
  binary = "eca";
  kind = "patchelf";
  libs = [ corePins.zlib ];

  category = "AI Coding Agents";

  meta = {
    description = "Editor Code Assistant (ECA) - AI pair programming capabilities agnostic of editor";
    homepage = "https://github.com/editor-code-assistant/eca";
    changelog = "https://github.com/editor-code-assistant/eca/releases";
    license = flake.lib.licenses.asl20;
    sourceProvenance = [ flake.lib.sourceTypes.binaryNativeCode ];
    maintainers = [ flake.lib.maintainers.zrubing ];
  };
}
