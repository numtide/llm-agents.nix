{
  lib,
  flake,
  mkUpdater,
  stdenv,
  fd,
  makeWrapper,
  ripgrep,
  platformSource,
  wrapBuddy,
  versionCheckHook,
  versionCheckHomeHook,
}:

let
  pname = "pi-bolt";
  source = platformSource {
    hashesFile = ./hashes.json;
    platforms = {
      x86_64-linux = "linux-x64";
      aarch64-linux = "linux-arm64";
      aarch64-darwin = "darwin-arm64";
    };
    urlTemplate = "https://github.com/opensec-git/Pi-Bolt/releases/download/bolt-v{version}/pi-bolt-{platform}.tar.xz";
  };
  inherit (source) version;
in
stdenv.mkDerivation {
  inherit pname version;

  inherit (source) src;

  nativeBuildInputs = [ makeWrapper ] ++ lib.optionals stdenv.hostPlatform.isLinux [ wrapBuddy ];

  # The executable embeds bun's bytecode at the end of the file; stripping it
  # corrupts the runtime.
  dontStrip = true;

  installPhase = ''
    runHook preInstall

    # The archive is a full install tree (docs, export-html templates, skills)
    # that the single executable resolves relative to its own path, so keep it
    # together and expose it through bin. The upstream executable is called
    # `pi`, which would collide with the `pi` package, hence `pi-bolt`.
    mkdir -p $out/share/pi-bolt
    cp -r . $out/share/pi-bolt

    # Provide fd and ripgrep so it does not download unpatched binaries into
    # ~/.pi/agent/bin, and disable the upstream update check (same as `pi`).
    makeWrapper $out/share/pi-bolt/pi $out/bin/pi-bolt \
      --prefix PATH : ${
        lib.makeBinPath [
          fd
          ripgrep
        ]
      } \
      --set PI_SKIP_VERSION_CHECK 1 \
      --set PI_TELEMETRY 0

    runHook postInstall
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [
    versionCheckHook
    versionCheckHomeHook
  ];
  versionCheckProgramArg = "--version";

  passthru.category = "AI Coding Agents";
  passthru.updater = mkUpdater (
    source.updater
    // {
      versionSource = {
        type = "text";
        url = "https://raw.githubusercontent.com/opensec-git/Pi-Bolt/pi-bolt/VERSION";
      };
    }
  );

  meta = with lib; {
    description = "Pi, the coding agent, compiled ahead of time to one native executable";
    homepage = "https://github.com/opensec-git/Pi-Bolt";
    changelog = "https://github.com/opensec-git/Pi-Bolt/releases/tag/bolt-v${version}";
    license = licenses.mit;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    maintainers = with flake.lib.maintainers; [ dachxy ];
    mainProgram = "pi-bolt";
    platforms = source.platforms;
  };
}
