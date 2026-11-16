{
  lib,
  rustPlatform,
  fetchFromGitHub,
  installAgentSkills,
  versionCheckHook,
  makeWrapper,
  pkg-config,
  fontconfig,
  freetype,
  libxcb,
  libxkbcommon,
  wayland,
  vulkan-loader,
  # Default X11 backend (Xvfb + Openbox), see upstream "Install" section.
  dbus,
  imagemagick,
  openbox,
  xauth,
  xclip,
  xdotool,
  xdpyinfo,
  xprop,
  xvfb,
  # Native KWin backend: the compositor itself comes from the host.
  wl-clipboard,
}:

rustPlatform.buildRustPackage (finalAttrs: {
  pname = "agent-workspace-linux";
  version = "0.6.4";

  src = fetchFromGitHub {
    owner = "agent-sh";
    repo = "agent-workspace-linux";
    tag = "v${finalAttrs.version}";
    hash = "sha256-pJdjk9YzXPMG4JLqHUMc/0Qg+eN97+6GMkuHXz26H8g=";
  };

  # gpui, gpui_platform and the cosmic protocols are git dependencies.
  cargoHash = "sha256-BgPwv6jM0p8qwg6QJ+V5oHATOPB4QRc1nGgAPHusrTw=";

  nativeBuildInputs = [
    installAgentSkills
    makeWrapper
    pkg-config
  ];

  buildInputs = [
    fontconfig
    freetype
    libxcb
    libxkbcommon
    wayland
  ];

  # The suites spawn Xvfb, nested compositors and session buses.
  doCheck = false;

  # The GPUI viewer loads Vulkan, Wayland and xkbcommon at run time.
  # The X11 backend tools are appended to PATH so that a host install
  # (or the compositor of a native backend such as kwin_wayland) wins.
  postFixup = ''
    patchelf $out/bin/agent-workspace-linux --add-rpath ${
      lib.makeLibraryPath [
        vulkan-loader
        wayland
        libxkbcommon
      ]
    }

    wrapProgram $out/bin/agent-workspace-linux \
      --suffix PATH : ${
        lib.makeBinPath [
          dbus
          imagemagick
          openbox
          xauth
          xclip
          xdotool
          xdpyinfo
          xprop
          xvfb
          wl-clipboard
        ]
      }
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [ versionCheckHook ];
  versionCheckProgramArg = "--version";

  passthru.category = "Utilities";

  meta = {
    description = "Isolated Linux desktop workspaces for AI agents, over MCP and CLI";
    homepage = "https://github.com/agent-sh/agent-workspace-linux";
    changelog = "https://github.com/agent-sh/agent-workspace-linux/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.mit;
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
    maintainers = with lib.maintainers; [ mrdev023 ];
    mainProgram = "agent-workspace-linux";
    platforms = lib.platforms.linux;
  };
})
