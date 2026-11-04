{
  lib,
  callPackage,
  stdenvNoCC,
  makeBinaryWrapper,
  t3code-unwrapped ? callPackage ./unwrapped.nix { },
  codex,
  claude-code,
  cursor-agent,
  grok,
  opencode,
  providerPackages ? [
    codex
    claude-code
    cursor-agent
    grok
    opencode
  ],
}:

let
  providerBinPath = lib.makeBinPath providerPackages;
  pathPrefixFlag = lib.optionalString (
    providerBinPath != ""
  ) "--prefix PATH : ${lib.escapeShellArg providerBinPath}";
  # Without this the desktop app falls back to process.execPath (bare electron)
  # for `Exec=` in the t3code:// URL handler entry it writes on Linux.
  launcherPathFlag = lib.optionalString stdenvNoCC.hostPlatform.isLinux ''--set-default T3CODE_DESKTOP_LAUNCHER_PATH "$desktop/bin/t3code-desktop"'';
in
stdenvNoCC.mkDerivation {
  pname = "t3code";
  inherit (t3code-unwrapped) version;

  outputs = [
    "out"
    "desktop"
  ];

  dontUnpack = true;
  strictDeps = true;

  nativeBuildInputs = [ makeBinaryWrapper ];

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/bin" "$desktop/bin"

    makeWrapper ${t3code-unwrapped}/bin/t3 "$out/bin/t3" \
      ${pathPrefixFlag}
    ln -s ${t3code-unwrapped}/share "$out/share"

    makeWrapper ${t3code-unwrapped.desktop}/bin/t3code-desktop \
      "$desktop/bin/t3code-desktop" \
      ${pathPrefixFlag} \
      ${launcherPathFlag} \
      --inherit-argv0
    ln -s ${t3code-unwrapped.desktop}/share "$desktop/share"

    ${lib.optionalString stdenvNoCC.hostPlatform.isDarwin ''
      sourceApp=${lib.escapeShellArg "${t3code-unwrapped.desktop}/Applications/${t3code-unwrapped.appName}.app"}
      targetApp="$desktop/Applications/${t3code-unwrapped.appName}.app"
      mkdir -p "$targetApp/Contents/MacOS"
      ln -s "$sourceApp/Contents/Info.plist" "$targetApp/Contents/Info.plist"
      ln -s "$sourceApp/Contents/Resources" "$targetApp/Contents/Resources"
      ln -s ../../../../bin/t3code-desktop \
        "$targetApp/Contents/MacOS/${t3code-unwrapped.appName}"
    ''}

    runHook postInstall
  '';

  passthru = {
    category = "AI Coding Agents";
    inherit providerPackages;
    # Keep the existing t3code updater targeting the unwrapped build inputs.
    inherit (t3code-unwrapped) pnpmDeps resourceMonitor src;
    unwrapped = t3code-unwrapped;
  };

  meta = t3code-unwrapped.meta // {
    description = "Control surface for coding agents";
  };
}
