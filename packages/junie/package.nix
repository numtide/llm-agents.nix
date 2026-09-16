{
  lib,
  flake,
  stdenv,
  platformSource,
  unzip,
  makeWrapper,
  formatelf,
  versionCheckHook,
  codesignCheckHook,
  zlib,
}:

let
  pname = "junie";
  source = platformSource {
    hashesFile = ./hashes.json;
    platforms = {
      x86_64-linux = "linux-amd64";
      aarch64-linux = "linux-aarch64";
      aarch64-darwin = "macos-aarch64";
    };
    urlTemplate = "https://github.com/JetBrains/junie/releases/download/{version}/junie-release-{version}-{platform}.zip";
  };
  inherit (source) version;
in
stdenv.mkDerivation {
  inherit pname;
  inherit (source) version src;

  nativeBuildInputs = [
    unzip
    makeWrapper
  ]
  ++ lib.optionals stdenv.hostPlatform.isLinux [ formatelf ];

  # The bundled JRE contains modules for AWT/sound/etc that we don't need for
  # the CLI; mark their deps optional so autoPatchelfHook doesn't fail.
  autoPatchelfIgnoreMissingDeps = [
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

  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [
    (lib.getLib stdenv.cc.cc) # libstdc++, libgcc_s
    zlib
  ];

  sourceRoot = ".";

  # Don't strip: the bundled JRE's jimage (lib/modules) gets corrupted and
  # macOS binaries are signed.
  dontStrip = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
  ''
  + (
    if stdenv.hostPlatform.isDarwin then
      # macOS archive ships a .app bundle plus a trivial `junie` shell
      # wrapper. We can't symlink to the launcher: fixupPhase rewrites
      # $out-internal symlinks to be relative, and the jpackage launcher
      # then readlink()s itself, gets a relative path, and tries to open
      # "/../Applications/junie.app/...". Use makeWrapper instead.
      ''
        mkdir -p $out/Applications
        cp -R Applications/junie.app $out/Applications/
        makeWrapper $out/Applications/junie.app/Contents/MacOS/junie $out/bin/junie
      ''
    else
      # Linux archive is a plain jpackage app-image: junie-app/{bin,lib}.
      ''
        mkdir -p $out/opt
        cp -r junie-app $out/opt/junie
        ln -s $out/opt/junie/bin/junie $out/bin/junie
      ''
  )
  + ''

    runHook postInstall
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [
    versionCheckHook
    codesignCheckHook
  ];
  codesignTeamId = "2ZEFAR8TH3";
  codesignSources = source.darwinSrcs;
  versionCheckProgramArg = "--version";
  # OpenJDK resolves user.home via getpwuid() and ignores $HOME. In the Nix
  # sandbox /etc/passwd lists the home directory as the literal string
  # `"/build"` (quotes included), so Junie tries to mkdir a path starting
  # with `/"` and blows up before it can print the version.
  versionCheckKeepEnvironment = [ "JAVA_TOOL_OPTIONS" ];
  preVersionCheck = ''
    export JAVA_TOOL_OPTIONS="-Duser.home=$(mktemp -d)"
  '';

  # Launching the app bundle from $out during versionCheckPhase makes macOS
  # attach a protected com.apple.macl xattr to junie.app. nix-daemon then
  # fails to canonicalise the output ("clearing flags of path ...: Operation
  # not permitted"). The xattr cannot be removed, but recreating the
  # directory entry (children are just rename()d) drops it.
  postInstallCheck = lib.optionalString stdenv.hostPlatform.isDarwin ''
    mv "$out/Applications/junie.app" "$out/Applications/.junie.app.tmp"
    mkdir "$out/Applications/junie.app"
    shopt -s dotglob
    mv "$out/Applications/.junie.app.tmp"/* "$out/Applications/junie.app/"
    shopt -u dotglob
    rmdir "$out/Applications/.junie.app.tmp"
  '';

  passthru.category = "AI Coding Agents";

  meta = with lib; {
    description = "Junie, JetBrains AI coding agent CLI";
    homepage = "https://github.com/JetBrains/junie";
    changelog = "https://github.com/JetBrains/junie/releases/tag/${version}";
    license = flake.lib.licenses.unfree;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    platforms = source.platforms;
    mainProgram = "junie";
    maintainers = with lib.maintainers; [
      mic92
      daspk04
    ];
  };
}
