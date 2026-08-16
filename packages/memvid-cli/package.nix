# memvid-cli (`memvid`, AI memory CLI) - built on corepkgs, the repo's
# nixpkgs-free packaging system. `mkPackage` fetches the prebuilt release artifact
# and wraps it. There is no ./hashes.json here (no nix-update source of truth), so
# the version + tarball hash live inline via coreFetchurl.
#
# memvid is a jpackage-style native launcher with a bundled JVM: the `memvid` ELF
# and its sibling .so files (libjvm, libawt, libtika_native, ...) live in one npm
# tarball dir. dir-install the whole tree so intra-tree deps resolve via $ORIGIN.
# The binary needs openssl + zlib; the bundled AWT/X11/sound libs are optional
# (headless CLI) so leave their SONAMEs missing, like autoPatchelfIgnoreMissingDeps.
{
  mkPackage,
  coreFetchurl,
  flake,
  corePins,
}:
let
  data = builtins.fromJSON (builtins.readFile ./hashes.json);
in
mkPackage {
  pname = "memvid-cli";
  inherit (data) version;
  mainProgram = "memvid";
  src = coreFetchurl {
    url = "https://registry.npmjs.org/@memvid/cli-linux-x64/-/cli-linux-x64-${data.version}.tgz";
    inherit (data) hash;
  };
  unpack = "tar";
  installDir = "package";
  entrypoint = "memvid";
  kind = "patchelf";
  libs = [
    corePins.openssl
    corePins.zlib
  ];
  # Force the bundled JVM headless so the optional AWT/X11/sound libs below are
  # never dlopen'd - the CLI has no GUI. Keeps ignoreMissing honest.
  setEnv = {
    _JAVA_AWT_HEADLESS = "true";
  };
  ignoreMissing = [
    "libasound.so.2"
    "libX11.so.6"
    "libXext.so.6"
    "libXi.so.6"
    "libXrender.so.1"
    "libXtst.so.6"
  ];

  category = "Memory & Code Intelligence";

  meta = {
    description = "AI memory CLI - crash-safe, single-file storage with semantic search";
    # Inline-pinned x86_64 binary only (mkPackage cannot yet read this
    # package's nested per-platform hashes.json); gate accordingly.
    platforms = [ "x86_64-linux" ];
    homepage = "https://memvid.com";
    changelog = "https://github.com/memvid/memvid/releases";
    license = flake.lib.licenses.asl20;
    # CLI is closed-source; upstream repo only contains the memvid-core library.
    sourceProvenance = [ flake.lib.sourceTypes.binaryNativeCode ];
    maintainers = [ flake.lib.maintainers.smdex ];
  };
}
