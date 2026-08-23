{
  lib,
  callPackage,
  stdenvNoCC,
  makeShellWrapper,
  nodejs_24,
  chatgpt-unwrapped ? callPackage ./unwrapped.nix { },
  chatgpt-runtime-python ?
    if stdenvNoCC.hostPlatform.system == "x86_64-linux" then
      callPackage ./runtime-python.nix { }
    else
      null,
  commandLineArgs ? "",
}:

stdenvNoCC.mkDerivation {
  pname = "chatgpt";
  inherit (chatgpt-unwrapped) version;

  dontUnpack = true;

  nativeBuildInputs = [ makeShellWrapper ];

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/bin"
    makeShellWrapper ${chatgpt-unwrapped}/bin/chatgpt "$out/bin/chatgpt" \
      --set CODEX_MCP_NODE_PATH ${lib.getExe nodejs_24} \
      ${
        lib.optionalString (
          chatgpt-runtime-python != null
        ) "--set PYTHON ${lib.getExe chatgpt-runtime-python}"
      } \
      --add-flags "\''${NIXOS_OZONE_WL:+\''${WAYLAND_DISPLAY:+--ozone-platform=wayland}}" \
      --add-flags ${lib.escapeShellArg commandLineArgs}
    ln -s ${chatgpt-unwrapped}/share "$out/share"

    runHook postInstall
  '';

  passthru = {
    category = "AI Coding Agents";
    runtimePython = chatgpt-runtime-python;
    unwrapped = chatgpt-unwrapped;
  };

  inherit (chatgpt-unwrapped) meta;
}
