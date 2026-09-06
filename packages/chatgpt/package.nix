{
  lib,
  stdenv,
  callPackage,
  stdenvNoCC,
  makeShellWrapper,
  replaceVars,
  formatelf,
  inotify-tools,
  curl,
  libxcrypt-legacy,
  nspr,
  nss,
  zlib,
  chatgpt-unwrapped ? callPackage ./unwrapped.nix { },
  commandLineArgs ? "",
}:

let
  # Libraries the downloaded codex-primary-runtime expects from the host.
  runtimeLibs = [
    stdenv.cc.cc.lib
    zlib
    libxcrypt-legacy
    curl
    nss
    nspr
  ];
  patchRuntime = replaceVars ./patch-runtime.sh {
    autoFormatelf = "${formatelf.bin}/bin/auto-formatelf";
    inotifywait = "${inotify-tools}/bin/inotifywait";
    dynamicLinker = "${stdenv.cc.bintools}/nix-support/dynamic-linker";
    libc = "${stdenv.cc.libc}/lib";
    libs = lib.concatMapStringsSep " " (p: "${lib.getLib p}/lib") runtimeLibs;
  };
in
stdenvNoCC.mkDerivation {
  pname = "chatgpt";
  inherit (chatgpt-unwrapped) version;

  dontUnpack = true;

  nativeBuildInputs = [ makeShellWrapper ];

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/bin"
    makeShellWrapper ${chatgpt-unwrapped}/bin/chatgpt "$out/bin/chatgpt" \
      ${lib.optionalString stdenv.hostPlatform.isLinux "--run '. ${patchRuntime}' --set-default DOTNET_SYSTEM_GLOBALIZATION_INVARIANT 1"} \
      --add-flags "\''${NIXOS_OZONE_WL:+\''${WAYLAND_DISPLAY:+--ozone-platform=wayland}}" \
      --add-flags ${lib.escapeShellArg commandLineArgs}
    ${lib.optionalString stdenv.hostPlatform.isLinux "ln -s ${chatgpt-unwrapped}/share \"\$out/share\""}

    runHook postInstall
  '';

  passthru = {
    category = "AI Coding Agents";
    unwrapped = chatgpt-unwrapped;
    inherit patchRuntime;
  };

  inherit (chatgpt-unwrapped) meta;
}
