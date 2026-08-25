{
  lib,
  callPackage,
  stdenvNoCC,
  makeShellWrapper,
  nodejs,
  bubblewrap,
  chatgpt-unwrapped ? callPackage ./unwrapped.nix { },
  # Keep proprietary runtime contents out of the default package and CI closure.
  withPrimaryRuntime ? false,
  chatgpt-runtime-python ? if withPrimaryRuntime then callPackage ./runtime-python.nix { } else null,
  chatgpt-primary-runtime ?
    if withPrimaryRuntime then
      callPackage ./runtime.nix {
        inherit chatgpt-runtime-python;
      }
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
      --set CODEX_MCP_NODE_PATH ${lib.getExe nodejs} \
      --prefix PATH : ${
        lib.makeBinPath [
          bubblewrap
          nodejs
        ]
      } \
      ${
        lib.optionalString (
          chatgpt-runtime-python != null
        ) "--set PYTHON ${lib.getExe chatgpt-runtime-python}"
      } \
      ${
        lib.optionalString (
          chatgpt-primary-runtime != null
        ) "--set CODEX_PRIMARY_RUNTIME_PATH ${chatgpt-primary-runtime}"
      } \
      --add-flags "\''${NIXOS_OZONE_WL:+\''${WAYLAND_DISPLAY:+--ozone-platform=wayland}}" \
      --add-flags ${lib.escapeShellArg commandLineArgs}
    ln -s ${chatgpt-unwrapped}/share "$out/share"

    runHook postInstall
  '';

  passthru = {
    category = "AI Coding Agents";
    primaryRuntime = chatgpt-primary-runtime;
    runtimePython = chatgpt-runtime-python;
    unwrapped = chatgpt-unwrapped;
    inherit withPrimaryRuntime;
  };

  inherit (chatgpt-unwrapped) meta;
}
