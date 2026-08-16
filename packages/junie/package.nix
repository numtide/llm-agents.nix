# junie (JetBrains AI coding agent CLI) - built on corepkgs, the repo's
# nixpkgs-free packaging system. version + per-platform hashes come from the
# shared ./hashes.json (the same file nix-update bumps).
#
# The Linux archive is a jpackage app-image: a native launcher (bin/junie) that
# finds its bundled JRE via ../lib. dir-install the whole junie-app tree, exec
# the nested launcher (kind = "patchelf" rewrites every ELF in the tree), and
# allow the JRE's optional AWT/sound/X11 libs to stay unresolved (the CLI never
# loads them) - like nixpkgs autoPatchelfIgnoreMissingDeps.
{
  mkPackage,
  corePins,
  flake,
}:
let
  # system -> {platform} URL token, shared by the build and (would-be) updater.
  platforms = {
    x86_64-linux = "linux-amd64";
    aarch64-linux = "linux-aarch64";
    aarch64-darwin = "macos-aarch64";
  };
  urlTemplate = "https://github.com/JetBrains/junie/releases/download/{version}/junie-release-{version}-{platform}.zip";
in
mkPackage {
  pname = "junie";
  hashesFile = ./hashes.json;
  inherit platforms urlTemplate;
  unpack = "zip";
  installDir = "junie-app";
  entrypoint = "bin/junie";
  mainProgram = "junie";
  kind = "patchelf";
  libs = [ corePins.zlib ];

  # The bundled JRE ships AWT/sound/X11 modules the CLI never loads; allow their
  # deps to stay unresolved instead of failing the ELF patch.
  ignoreMissing = [
    "libasound.so.2"
    "libfreetype.so.6"
    "libharfbuzz.so.0"
    "libgif.so.7"
    "libjpeg.so.8"
    "liblcms2.so.2"
    "libpng16.so.16"
    "libpcsclite.so.1"
    "libwayland-client.so.0"
    "libwayland-cursor.so.0"
    "libX11.so.6"
    "libXext.so.6"
    "libXi.so.6"
    "libXrender.so.1"
    "libXtst.so.6"
  ];

  category = "AI Coding Agents";

  meta = {
    description = "Junie, JetBrains AI coding agent CLI";
    # Linux only for now: the darwin JRE dir-install path is not yet handled by
    # the corepkgs darwin builder (needs a darwin machine to verify).
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
    homepage = "https://github.com/JetBrains/junie";
    changelog = "https://github.com/JetBrains/junie/releases";
    license = flake.lib.licenses.unfree;
    sourceProvenance = [ flake.lib.sourceTypes.binaryNativeCode ];
    maintainers = [
      flake.lib.maintainers.mic92
      flake.lib.maintainers.daspk04
    ];
  };
}
