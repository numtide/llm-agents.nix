{
  lib,
  callPackage,
  stdenvNoCC,
  makeWrapper,
  bun,
  nodejs,
  openssh,
  git,
  herdr,
  herdr-core,
  ovis-unwrapped ? callPackage ./unwrapped.nix { },
  # The terminal server ovis drives: herdr's TUI server or herdr-core (the Herdr app's core).
  runtime ? "herdr",
}:

assert lib.assertOneOf "runtime" runtime [
  "herdr"
  "herdr-core"
];

let
  # A user-installed hc wins, as in the herdr-app wrapper, so clients sharing one core agree on its version.
  # herdr-core is named outright: with no OVIS_RUNTIME ovis keeps herdr unless the Herdr app is installed.
  runtimeFlags =
    if runtime == "herdr" then
      "--prefix PATH : ${lib.makeBinPath [ herdr ]}"
    else
      "--set-default OVIS_RUNTIME herdr-core --suffix PATH : ${lib.makeBinPath [ herdr-core ]}";
in
stdenvNoCC.mkDerivation {
  pname = "ovis";
  inherit (ovis-unwrapped) version;

  dontUnpack = true;
  strictDeps = true;

  nativeBuildInputs = [ makeWrapper ];

  # The unmanaged entrypoint leaves updates to Nix rather than replacing itself.
  installPhase = ''
    runHook preInstall
    makeWrapper ${lib.getExe bun} $out/bin/ovis \
      --add-flags "${ovis-unwrapped}/share/ovis/server/index.ts" \
      --set-default OVIS_TELEMETRY 0 \
      --prefix PATH : ${
        lib.makeBinPath [
          nodejs
          openssh
          git
        ]
      } \
      ${runtimeFlags}
    runHook postInstall
  '';

  passthru = {
    category = "Workflow & Project Management";
    inherit runtime;
    # Keep the updater targeting the unwrapped build inputs.
    inherit (ovis-unwrapped) ptySidecar updater;
    unwrapped = ovis-unwrapped;
    # Each links to `herdr-web-ui.js` in that agent's extensions directory, as upstream's installers write it.
    integrations = {
      pi = "${ovis-unwrapped}/share/ovis/integrations/pi/herdr-web-ui.js";
      gjc = "${ovis-unwrapped}/share/ovis/integrations/gjc/herdr-web-ui.js";
    };
  };

  meta = ovis-unwrapped.meta // {
    mainProgram = "ovis";
  };
}
