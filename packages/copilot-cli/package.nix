# copilot-cli (GitHub Copilot CLI) - built on corepkgs, the repo's nixpkgs-free
# packaging system. Since 1.0.64 the @github/copilot npm package is just a
# loader that resolves and spawns a per-platform package
# (@github/copilot-<platform>-<arch>), which ships the actual Node SEA binary
# plus bundled ripgrep/tgrep and native .node modules. version + per-platform
# hashes come from the shared ./hashes.json (the same file nix-update bumps).
#
# The `copilot` binary is a Node single-executable application (SEA) with an
# appended payload: formatelf cannot rewrite its truncated headers and any ELF
# edit corrupts it, so kind = "loader" leaves it byte-intact and invokes the
# pinned glibc loader through the wrapper. dir-install the whole tree so the SEA
# finds its bundled rg/tgrep and native modules. The bundled webview module
# needs GTK/webkit/wayland libs the CLI never loads; allow them to stay
# unresolved (like nixpkgs autoPatchelfIgnoreMissingDeps).
{
  mkPackage,
  mkUpdater,
  corePins,
  flake,
}:
let
  # system -> {platform} URL token, shared by the build and the updater.
  platforms = {
    x86_64-linux = "linux-x64";
    aarch64-linux = "linux-arm64";
    aarch64-darwin = "darwin-arm64";
  };
  urlTemplate = "https://registry.npmjs.org/@github/copilot-{platform}/-/copilot-{platform}-{version}.tgz";
in
mkPackage {
  pname = "copilot-cli";
  hashesFile = ./hashes.json;
  inherit platforms urlTemplate;
  unpack = "tar";
  installDir = "package";
  entrypoint = "copilot";
  mainProgram = "copilot";
  kind = "loader";
  libs = [ corePins.zlib ];

  # --set-default COPILOT_AUTO_UPDATE false keeps the immutable Nix store binary
  # from trying to replace itself.
  setEnv = {
    COPILOT_AUTO_UPDATE = "false";
  };

  # The bundled webview .node module is dlopen'd only in GUI mode; the CLI never
  # loads it, so allow its GTK/webkit/wayland deps to stay unresolved.
  ignoreMissing = [
    "libwebkit2gtk-4.1.so.0"
    "libgtk-3.so.0"
    "libgdk-3.so.0"
    "libcairo.so.2"
    "libgdk_pixbuf-2.0.so.0"
    "libsoup-3.0.so.0"
    "libgio-2.0.so.0"
    "libjavascriptcoregtk-4.1.so.0"
    "libgobject-2.0.so.0"
    "libglib-2.0.so.0"
    "libwayland-client.so.0"
    "libdbus-1.so.3"
    "libxdo.so.3"
  ];

  category = "AI Coding Agents";
  updater = mkUpdater {
    kind = "platform";
    inherit urlTemplate platforms;
    versionSource = {
      type = "npm";
      package = "@github/copilot";
    };
  };

  meta = {
    description = "GitHub Copilot CLI brings the power of Copilot coding agent directly to your terminal.";
    homepage = "https://github.com/github/copilot-cli";
    changelog = "https://github.com/github/copilot-cli/releases";
    license = flake.lib.licenses.unfree;
    sourceProvenance = [ flake.lib.sourceTypes.binaryNativeCode ];
  };
}
