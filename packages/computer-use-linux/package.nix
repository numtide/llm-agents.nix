{
  lib,
  rustPlatform,
  fetchFromGitHub,
  installAgentSkills,
  makeWrapper,
  glib,
  libxkbcommon,
}:

rustPlatform.buildRustPackage (finalAttrs: {
  pname = "computer-use-linux";
  version = "0.7.55";

  src = fetchFromGitHub {
    owner = "agent-sh";
    repo = "computer-use-linux";
    tag = "v${finalAttrs.version}";
    hash = "sha256-UAbTZHMTHnCOwH4mYzZXNophtNbPbouN4naPrFWzFV8=";
  };

  cargoHash = "sha256-QJzvgQKmQg1GAXQAOZdIAfwlJgI2IxUG3J+jmxYAuK0=";

  nativeBuildInputs = [
    installAgentSkills
    makeWrapper
  ];

  # The suites drive the live AT-SPI bus, portals and compositor of the host.
  doCheck = false;

  # plugins/ carries a copy of the same skill for the Claude Code plugin;
  # install only the top-level one.
  dontInstallAgentSkills = true;
  postInstall = ''
    installSkill skills/computer-use-linux
  '';

  # xkbcommon-dl opens libxkbcommon at run time to verify literal text
  # against the active keymap.
  #
  # gdbus probes the KWin and GNOME Shell window backends, and gsettings
  # enables the GNOME AT-SPI bridge (`setup`); both are desktop-agnostic,
  # so ship them, appended to PATH so a host glib wins.
  #
  # The compositor helpers (ydotool, wtype, xdotool, hyprctl, kscreen-doctor,
  # gnome-extensions, ...) are deliberately left to the host: which ones are
  # used depends on the running desktop, and `computer-use-linux doctor`
  # reports what is missing. The COSMIC helper and the indicator overlay are
  # found next to the main binary, so they only need to share $out/bin.
  postFixup = ''
    patchelf $out/bin/computer-use-linux --add-rpath ${lib.makeLibraryPath [ libxkbcommon ]}
    wrapProgram $out/bin/computer-use-linux \
      --suffix PATH : ${lib.makeBinPath [ glib ]}
  '';

  # The CLI has no --version flag (the version is only reported to MCP
  # clients in server_info), so smoke-test the argument parser instead.
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    $out/bin/computer-use-linux --help | grep -q 'doctor'
    runHook postInstallCheck
  '';

  passthru.category = "Utilities";

  meta = {
    description = "Native Linux desktop control for AI agents over MCP and CLI (AT-SPI, Wayland/X11 input, screenshots)";
    homepage = "https://github.com/agent-sh/computer-use-linux";
    changelog = "https://github.com/agent-sh/computer-use-linux/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.mit;
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
    maintainers = with lib.maintainers; [ mrdev023 ];
    mainProgram = "computer-use-linux";
    platforms = lib.platforms.linux;
  };
})
