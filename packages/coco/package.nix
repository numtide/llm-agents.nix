{
  lib,
  flake,
  stdenv,
  platformSource,
  mkUpdater,
  makeWrapper,
  python3,
  formatelf,
  wrapBuddy,
  rcodesign,
  versionCheckHook,
  versionCheckHomeHook,
  nodejs_22,
  openssl,
  zlib,
  libxcrypt-legacy,
  alsa-lib,
  which,
  bubblewrap,
  socat,
  ripgrep,
}:

let
  baseUrl = "https://sfc-repo.snowflakecomputing.com/cortex-code-cli/a4643c4278";
  platforms = {
    x86_64-linux = "linux-amd64";
    aarch64-linux = "linux-arm64";
    aarch64-darwin = "darwin-arm64";
  };
  source = platformSource {
    hashesFile = ./hashes.json;
    inherit platforms;
    # Snowflake 404s on a literal `+` in the path, hence {versionEnc}.
    urlTemplate = "${baseUrl}/{versionEnc}/coco-{versionEnc}-{platform}.tar.gz";
  };
  displayVersion = lib.head (lib.splitString "+" source.version);
  runtimePath = lib.makeBinPath (
    [
      nodejs_22
      openssl
    ]
    ++ lib.optionals stdenv.hostPlatform.isLinux [
      which
      socat
    ]
  );
in
stdenv.mkDerivation {
  pname = "coco";
  inherit (source) version src;

  nativeBuildInputs = [
    makeWrapper
    python3
  ]
  ++ lib.optionals stdenv.hostPlatform.isLinux [
    formatelf
    wrapBuddy
  ]
  ++ lib.optionals stdenv.hostPlatform.isDarwin [ rcodesign ];

  buildInputs =
    lib.optionals stdenv.hostPlatform.isLinux [
      (lib.getLib stdenv.cc.cc)
      zlib
      libxcrypt-legacy
    ]
    ++ lib.optionals (stdenv.hostPlatform.isLinux && stdenv.hostPlatform.isx86_64) [ alsa-lib ];

  # Resolves to the bundled libpython at runtime; formatelf can't see that.
  autoPatchelfIgnoreMissingDeps = [ "$ORIGIN/../lib/libpython3.12.so.1.0" ];

  # cortex is an ELF with a JS payload appended; stripping would truncate it.
  dontStrip = true;
  dontWrapBuddy = true;

  installPhase = ''
    runHook preInstall

    # The binary derives its version from a .../share/cortex/<version>/ execPath.
    releaseDir=$out/share/cortex/${source.version}
    mkdir -p "$releaseDir"
    cp -r . "$releaseDir"
    python3 ${./patch-payload.py} "$releaseDir/cortex"

    ${lib.optionalString stdenv.hostPlatform.isDarwin ''
      # Upstream rg links against Homebrew's pcre2.
      ln -sf ${lib.getExe ripgrep} "$releaseDir/rg"
      rcodesign sign --code-signature-flags linker-signed "$releaseDir/cortex"
    ''}
    ${lib.optionalString stdenv.hostPlatform.isLinux ''
      wrapBuddy --no-recurse "$releaseDir/cortex"
    ''}

    # bwrap goes last: a host bwrap may carry the setuid bit or AppArmor
    # profile the distro requires.
    makeWrapper "$releaseDir/cortex" $out/bin/cortex \
      --prefix PATH : ${runtimePath} \
      ${lib.optionalString stdenv.hostPlatform.isLinux "--suffix PATH : ${lib.makeBinPath [ bubblewrap ]}"} \
      --set OPENSSL_BIN ${lib.getExe openssl}

    runHook postInstall
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [
    versionCheckHook
    versionCheckHomeHook
  ];
  preVersionCheck = "version=${displayVersion}";

  passthru.category = "AI Coding Agents";
  passthru.updater = mkUpdater {
    kind = "manifest-checksums";
    versionSource = {
      type = "text";
      url = "${baseUrl}/stable_version.txt";
    };
    manifestUrl = "${baseUrl}/{versionEnc}/manifest.json";
    checksumPath = "packages.{platform}.checksum";
    # Manifest nests os.arch where the tarball name uses os-arch.
    platforms = lib.mapAttrs (_: lib.replaceStrings [ "-" ] [ "." ]) platforms;
    # Snowflake moves the stable pointer backwards on rollbacks.
    versionPolicy = "follow_pointer";
  };

  meta = with lib; {
    description = "Snowflake Cortex Code CLI, an AI coding agent for Snowflake";
    homepage = "https://docs.snowflake.com/en/user-guide/cortex-code/cortex-code-cli";
    changelog = "https://docs.snowflake.com/en/user-guide/cortex-code/changelog";
    license = flake.lib.licenses.unfree;
    sourceProvenance = with sourceTypes; [ binaryNativeCode ];
    maintainers = with flake.lib.maintainers; [ frankzvitale ];
    platforms = source.platforms;
    mainProgram = "cortex";
  };
}
