{
  lib,
  flake,
  stdenv,
  platformSource,
  makeWrapper,
  wrapBuddy,
  versionCheckHook,
  codesignCheckHook,
  bubblewrap,
  socat,
  mkUpdater,
  disableTelemetry ? false,
}:

let
  source = platformSource {
    hashesFile = ./hashes.json;
    platforms = {
      x86_64-linux = "linux-x64";
      aarch64-linux = "linux-arm64";
      aarch64-darwin = "darwin-arm64";
    };
    urlTemplate = "https://storage.googleapis.com/claude-code-dist-86c565f3-f756-42ad-8dfa-d59b1c096819/claude-code-releases/{version}/{platform}/claude";
  };
in
stdenv.mkDerivation {
  pname = "claude-code";
  inherit (source) version src;

  dontUnpack = true;

  nativeBuildInputs = [ makeWrapper ] ++ lib.optionals stdenv.hostPlatform.isLinux [ wrapBuddy ];

  dontStrip = true; # do not mess with the bun runtime

  installPhase = ''
    runHook preInstall

    install -Dm755 $src $out/bin/claude

    runHook postInstall
  '';

  # Disable auto-updates and installation method warnings.
  # See: https://github.com/anthropics/claude-code/issues/15592
  #
  # DISABLE_TELEMETRY and CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC are NOT set
  # by default: both break remote-control and potentially other features.
  # Use disableTelemetry = true to opt in to disabling them.
  # See: https://github.com/numtide/llm-agents.nix/issues/2811
  # See: https://github.com/anthropics/claude-code/issues/28098#issuecomment-3957698158
  #
  # Uses a single wrapProgram call to avoid double-wrapping which causes the
  # process to show as ".claude-wrapped_" instead of "claude" in ps/htop.
  # --argv0 ensures the process name is preserved through the wrapper.
  postFixup = ''
    wrapProgram $out/bin/claude \
      --argv0 claude \
      --set DISABLE_AUTOUPDATER 1 \
      --set-default DISABLE_NON_ESSENTIAL_MODEL_CALLS 1 \
      ${lib.optionalString disableTelemetry "--set DISABLE_TELEMETRY 1 --set CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC 1"} \
      --set DISABLE_INSTALLATION_CHECKS 1 ${lib.optionalString stdenv.hostPlatform.isLinux "--prefix PATH : ${
        lib.makeBinPath [
          bubblewrap
          socat
        ]
      }"}
  '';

  # Bun links against /usr/lib/libicucore.A.dylib which needs ICU data from
  # /usr/share/icu/ at runtime for Intl.Segmenter. The Nix macOS sandbox
  # blocks access to /usr/share/icu/, causing "failed to initialize Segmenter".
  # Disable the sandbox for this derivation on macOS (requires sandbox=relaxed).
  __noChroot = stdenv.hostPlatform.isDarwin;

  doInstallCheck = true;
  nativeInstallCheckInputs = [
    versionCheckHook
    codesignCheckHook
  ];
  codesignTeamId = "Q6L2SF6YDW";
  codesignSources = source.darwinSrcs;

  passthru.category = "AI Coding Agents";
  passthru.updater = mkUpdater {
    kind = "manifest-checksums";
    versionSource = {
      type = "text";
      url = "https://storage.googleapis.com/claude-code-dist-86c565f3-f756-42ad-8dfa-d59b1c096819/claude-code-releases/latest";
    };
    manifestUrl = "https://storage.googleapis.com/claude-code-dist-86c565f3-f756-42ad-8dfa-d59b1c096819/claude-code-releases/{version}/manifest.json";
    checksumPath = "platforms.{platform}.checksum";
    # Reuse the build's nix-system -> manifest-token map (the same tokens key
    # both the download URL and the manifest checksums).
    platforms = source.updater.platforms;
    # Anthropic yanks bad releases by repointing `latest`, so follow it down.
    versionPolicy = "follow_pointer";
  };

  meta = with lib; {
    description = "Agentic coding tool that lives in your terminal, understands your codebase, and helps you code faster";
    homepage = "https://claude.ai/code";
    changelog = "https://github.com/anthropics/claude-code/releases";
    license = flake.lib.licenses.unfree;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    maintainers = with maintainers; [
      malo
      omarjatoi
      ryoppippi
    ];
    mainProgram = "claude";
    platforms = source.platforms;
  };
}
