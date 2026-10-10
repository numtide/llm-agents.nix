{
  lib,
  flake,
  buildGoModule,
  buildNpmPackage,
  fetchFromGitHub,
  pkg-config,
  wrapGAppsHook3,
  gtk3,
  webkitgtk_4_1,
  portaudio,
  libx11,
  libxtst,
  libxinerama,
  libxrandr,
  libxt,
  libxcb,
  libxkbcommon,
  tmux,
}:

let
  pname = "asmgr-desktop";
  version = "1.1.19";

  src = fetchFromGitHub {
    owner = "izll";
    repo = "agent-session-manager-desktop";
    tag = "v${version}";
    hash = "sha256-xqcpBfDDXT4Mwd0+PZTG/zM/GToCFX10oZIbp32EdtU=";
  };

  # Svelte UI, embedded into the Go binary (//go:embed all:frontend/dist).
  # The Wails bindings under frontend/wailsjs are committed upstream, so the
  # wails CLI is not needed.
  frontend = buildNpmPackage {
    pname = "${pname}-frontend";
    inherit version src;
    sourceRoot = "${src.name}/frontend";
    npmDepsHash = "sha256-Idyh0ILwVPO47D1NA+wu6+mz/97zq2bDVWYdczmmFb0=";
    installPhase = ''
      runHook preInstall
      cp -r dist $out
      runHook postInstall
    '';
  };
in
buildGoModule {
  inherit pname version src;

  # go mod vendor drops the C sources that go-webrtcvad, gohook and robotgo
  # keep in directories without Go files; the module cache keeps them.
  proxyVendor = true;
  vendorHash = "sha256-YtxSQHghyk9gOAotIFDZ2sOiEYmHXjx+CuS4iRRgqcg=";

  # The in-app updater installs the upstream .deb/.rpm through pkexec and
  # /usr/bin/dpkg or rpm. Report automatic installation as unsupported, so the
  # update dialog only shows the manual hint instead of failing.
  postPatch = ''
    substituteInPlace updater/updater.go \
      --replace-fail 'case "linux":' 'case "linux-nix-store":'
  '';

  nativeBuildInputs = [
    pkg-config
    wrapGAppsHook3
  ];

  buildInputs = [
    gtk3
    webkitgtk_4_1
    portaudio
    libx11
    libxtst
    libxinerama
    libxrandr
    libxt
    libxcb
    libxkbcommon
  ];

  env.CGO_ENABLED = "1";

  # What `wails build -tags webkit2_41` passes to go build
  tags = [
    "desktop"
    "production"
    "webkit2_41"
  ];

  ldflags = [
    "-s"
    "-w"
    "-X main.Version=${version}"
  ];

  subPackages = [ "." ];

  preBuild = ''
    rm -rf frontend/dist
    cp -r ${frontend} frontend/dist
  '';

  # Remote servers get the asmgrd helper for their own architecture, looked up
  # as helpers/asmgrd-linux-<arch> next to the executable. Static, like the
  # upstream development fallback, so it runs whatever the server's libc.
  postBuild = ''
    for arch in amd64 arm64; do
      GOOS=linux GOARCH=$arch CGO_ENABLED=0 \
        go build -trimpath -ldflags "-s -w" \
          -o helpers/asmgrd-linux-$arch ./cmd/asmgrd
    done
  '';

  # The Go tests drive tmux, git and a display.
  doCheck = false;

  # The binary lives in libexec, next to its helpers/ directory; bin only
  # holds the wrapper. tmux is a runtime requirement (sessions run inside it).
  dontWrapGApps = true;
  postInstall = ''
    install -Dm755 $out/bin/asmgr-desktop $out/libexec/asmgr-desktop/asmgr-desktop
    rm $out/bin/asmgr-desktop
    install -Dm755 -t $out/libexec/asmgr-desktop/helpers helpers/asmgrd-linux-*

    install -Dm644 build/asmgr-desktop.desktop $out/share/applications/asmgr-desktop.desktop
    install -Dm644 build/appicon.png $out/share/icons/hicolor/512x512/apps/asmgr-desktop.png
  '';

  postFixup = ''
    makeWrapper $out/libexec/asmgr-desktop/asmgr-desktop $out/bin/asmgr-desktop \
      "''${gappsWrapperArgs[@]}" \
      --prefix PATH : ${lib.makeBinPath [ tmux ]}
  '';

  passthru = {
    inherit frontend;
    category = "Utilities";
  };

  meta = with lib; {
    description = "Desktop GUI to run and manage multiple AI coding-agent sessions (Claude, Codex, Gemini, Aider, ...) side by side";
    homepage = "https://github.com/izll/agent-session-manager-desktop";
    changelog = "https://github.com/izll/agent-session-manager-desktop/releases/tag/v${version}";
    license = licenses.mit;
    sourceProvenance = with sourceTypes; [ fromSource ];
    maintainers = with flake.lib.maintainers; [ tvdu29 ];
    mainProgram = "asmgr-desktop";
    platforms = platforms.linux;
  };
}
