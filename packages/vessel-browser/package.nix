{
  lib,
  flake,
  buildNpmPackage,
  fetchFromGitHub,
  electron_42,
  copyDesktopItems,
  makeDesktopItem,
  makeWrapper,
}:

buildNpmPackage rec {
  npmDepsFetcherVersion = 2;
  pname = "vessel-browser";
  version = "0.1.187";

  src = fetchFromGitHub {
    owner = "unmodeled-tyler";
    repo = "vessel-browser";
    tag = "v${version}";
    hash = "sha256-CJw26MBiYj4LlvhHc+KZzaPhylYmoDczugj9W2XsX1c=";
  };

  npmDepsHash = "sha256-bfXEZVD7CV6jeiu3kXHoVv+tpGwYg7WHSNZMtiF6vcw=";

  nativeBuildInputs = [
    copyDesktopItems
    makeWrapper
  ];

  env.ELECTRON_SKIP_BINARY_DOWNLOAD = "1";

  npmFlags = [ "--ignore-scripts" ];

  preBuild = ''
    # Ensure our electron major version matches what upstream expects.
    # This will fail loudly on version bumps instead of silently diverging.
    upstream_electron=$(node -p "require('./package.json').devDependencies.electron")
    upstream_major=''${upstream_electron#^}
    upstream_major=''${upstream_major%%.*}
    nix_major=${lib.versions.major electron_42.version}
    if [[ "$upstream_major" != "$nix_major" ]]; then
      echo "error: upstream expects electron $upstream_electron (major $upstream_major), but we provide electron ${electron_42.version} (major $nix_major)"
      echo "Update the electron_42 input in package.nix to match."
      exit 1
    fi

    # Upstream's release CI stamps the tag version into package.json
    # (the repo keeps a 0.1.0 placeholder), so app.getVersion() and the
    # in-app update check report the real version.
    npm pkg set version="${version}"
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/share/vessel-browser
    cp -r out package.json $out/share/vessel-browser/

    # The main process resolves the window icon relative to app.getAppPath().
    install -Dm644 resources/vessel-icon.png $out/share/vessel-browser/resources/vessel-icon.png
    install -Dm644 resources/vessel-icon.png $out/share/pixmaps/vessel-browser.png

    # electron-vite externalizes production dependencies (MCP SDK, AI SDKs,
    # ...), so they must be shipped in node_modules next to the bundle.
    npm prune --omit=dev
    # npm prune leaves behind empty scope directories of removed dev deps
    find node_modules -type d -empty -delete
    cp -r node_modules $out/share/vessel-browser/

    makeWrapper ${lib.getExe electron_42} $out/bin/vessel-browser \
      --add-flags $out/share/vessel-browser \
      --set-default ELECTRON_FORCE_IS_PACKAGED 1

    runHook postInstall
  '';

  desktopItems = [
    (makeDesktopItem {
      name = "vessel-browser";
      desktopName = "Vessel Browser";
      comment = "AI-native web browser for autonomous agents with human supervision";
      exec = "vessel-browser %U";
      icon = "vessel-browser";
      categories = [
        "Network"
        "WebBrowser"
      ];
      mimeTypes = [
        "text/html"
        "x-scheme-handler/http"
        "x-scheme-handler/https"
      ];
      startupWMClass = "Vessel";
    })
  ];

  passthru.category = "AI Assistants";

  meta = {
    description = "Agent-oriented browser with durable state and MCP control";
    homepage = "https://github.com/unmodeled-tyler/vessel-browser";
    changelog = "https://github.com/unmodeled-tyler/vessel-browser/releases/tag/v${version}";
    license = lib.licenses.mit;
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
    maintainers = with flake.lib.maintainers; [ smdex ];
    mainProgram = "vessel-browser";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
  };
}
