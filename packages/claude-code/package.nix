{
  lib,
  stdenv,
  fetchurl,
  makeWrapper,
  wrapBuddy,
  versionCheckHook,
  bubblewrap,
  socat,
}:

let
  versionData = builtins.fromJSON (builtins.readFile ./hashes.json);
  inherit (versionData) version hashes;

  platformMap = {
    x86_64-linux = "linux-x64";
    aarch64-linux = "linux-arm64";
    x86_64-darwin = "darwin-x64";
    aarch64-darwin = "darwin-arm64";
  };

  platform = stdenv.hostPlatform.system;
  platformSuffix = platformMap.${platform} or (throw "Unsupported system: ${platform}");
in
stdenv.mkDerivation {
  pname = "claude-code";
  inherit version;

  src = fetchurl {
    url = "https://storage.googleapis.com/claude-code-dist-86c565f3-f756-42ad-8dfa-d59b1c096819/claude-code-releases/${version}/${platformSuffix}/claude";
    hash = hashes.${platform};
  };

  dontUnpack = true;

  nativeBuildInputs = [ makeWrapper ] ++ lib.optionals stdenv.hostPlatform.isLinux [ wrapBuddy ];

  dontStrip = true; # do not mess with the bun runtime

  installPhase = ''
    runHook preInstall

    install -Dm755 $src $out/bin/claude

    runHook postInstall
  '';

  # Disable auto-updates, telemetry, and installation method warnings
  # See: https://github.com/anthropics/claude-code/issues/15592
  #
  # Uses a single wrapProgram call to avoid double-wrapping which causes the
  # process to show as ".claude-wrapped_" instead of "claude" in ps/htop.
  # --argv0 ensures the process name is preserved through the wrapper.
  postFixup = ''
    wrapProgram $out/bin/claude \
      --argv0 claude \
      --set DISABLE_AUTOUPDATER 1 \
      --set-default CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC 1 \
      --set-default DISABLE_NON_ESSENTIAL_MODEL_CALLS 1 \
      --set-default DISABLE_TELEMETRY 1 \
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
  nativeInstallCheckInputs = [ versionCheckHook ];

  passthru.category = "AI Coding Agents";

  meta = with lib; {
    description = "Agentic coding tool that lives in your terminal, understands your codebase, and helps you code faster";
    homepage = "https://claude.ai/code";
    changelog = "https://github.com/anthropics/claude-code/releases";
    license = licenses.unfree;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    maintainers = with maintainers; [
      malo
      omarjatoi
      ryoppippi
    ];
    mainProgram = "claude";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
      "x86_64-darwin"
      "aarch64-darwin"
    ];
  };
}
