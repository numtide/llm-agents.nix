{
  lib,
  flake,
  stdenv,
  platformSource,
  mkUpdater,
  fetchzip,
  makeWrapper,
  writeShellScriptBin,
  python3,
  formatelf,
  wrapBuddy,
  rcodesign,
  versionCheckHook,
  versionCheckHomeHook,
  nodejs_22,
  openssl,
  coreutils,
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
  whichShim = writeShellScriptBin "which" ''
    if [ "$#" -eq 1 ] && [ "$1" = cocobox ]; then
      exec ${lib.getExe which} "$@" 2>/dev/null
    fi

    exec ${lib.getExe which} "$@"
  '';
  commonRuntimePath = lib.makeBinPath [
    nodejs_22
    openssl
  ];
  linuxExternalRuntimePath = lib.makeBinPath [
    whichShim
    socat
  ];
  linuxBubblewrapPath = lib.makeBinPath [ bubblewrap ];
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

  # CoCo embeds the sandbox-runtime 0.0.45 resolver. Newer releases changed
  # apply-seccomp's interface and no longer ship the separate BPF program.
  sandboxRuntimeSrc = fetchzip {
    url = "https://registry.npmjs.org/@anthropic-ai/sandbox-runtime/-/sandbox-runtime-0.0.45.tgz";
    hash = "sha256-zTAsk5cffSkmrMhWG61WpudDHtwFSwEeqmIKqxNioCo=";
  };
  seccompArch = if stdenv.hostPlatform.isx86_64 then "x64" else "arm64";

  releaseDir = "${placeholder "out"}/share/cortex/${source.version}";
  runtimeInit = ''
    releaseDir=${lib.escapeShellArg releaseDir}
    storeName="''${releaseDir#/nix/store/}"
    storeName="''${storeName%%/*}"
    runtimeRoot="''${XDG_CACHE_HOME:-''${HOME:?HOME must be set}/.cache}/cortex-code/nix/$storeName"

    if [ ! -d "$runtimeRoot" ]; then
      (
        ${coreutils}/bin/mkdir -p "''${runtimeRoot%/*}"
        runtimeStage=$(${coreutils}/bin/mktemp -d "$runtimeRoot.tmp.XXXXXXXXXX")
        trap '${coreutils}/bin/rm -rf -- "$runtimeStage"' EXIT

        for entry in "$releaseDir"/*; do
          name="''${entry##*/}"
          if [ "$name" != openssl ]; then
            ${coreutils}/bin/ln -s "$entry" "$runtimeStage/$name"
          fi
        done

        # The bundled runtime rewrites openssl.cnf after generating the per-user
        # fipsmodule.cnf. Keep only this small subtree writable outside the store.
        # Some upstream archives (including ARM Linux) omit the FIPS bundle.
        if [ -d "$releaseDir/openssl" ]; then
          ${coreutils}/bin/cp -R "$releaseDir/openssl" "$runtimeStage/openssl"
          ${coreutils}/bin/chmod -R u+w "$runtimeStage/openssl"
        fi

        # Publish the complete tree atomically. If another launch won the race,
        # keep its tree (including any OpenSSL changes) and discard our staging.
        ${coreutils}/bin/mv -T --no-clobber "$runtimeStage" "$runtimeRoot"
      )
    fi

    export COCO_DIST_DIR="$runtimeRoot"
  '';
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
  ++ lib.optionals stdenv.hostPlatform.isDarwin [
    rcodesign
  ];

  buildInputs =
    lib.optionals stdenv.hostPlatform.isLinux [
      (lib.getLib stdenv.cc.cc)
      zlib
      libxcrypt-legacy
    ]
    ++ lib.optionals (stdenv.hostPlatform.isLinux && stdenv.hostPlatform.isx86_64) [
      alsa-lib
    ];

  # This literal $ORIGIN dependency resolves to the bundled Python library at
  # runtime, but formatelf cannot resolve it statically.
  autoPatchelfIgnoreMissingDeps = [
    "$ORIGIN/../lib/libpython3.12.so.1.0"
  ];

  # The cortex executable carries an embedded JS payload after the ELF.
  dontStrip = true;
  dontWrapBuddy = true;

  installPhase = ''
    runHook preInstall

    releaseDir=$out/share/cortex/${source.version}
    mkdir -p "$releaseDir" $out/bin
    cp -r . "$releaseDir"

    # The binary only recognizes releases installed in a per-user directory.
    # Relax that prefix guard so its existing parser accepts the Nix store's
    # share/cortex/<version> layout. Keep both edits byte-for-byte the same
    # length so the embedded payload offsets remain valid.
    ${lib.getExe python3} - "$releaseDir/cortex" <<'PY'
    import pathlib
    import re
    import sys

    path = pathlib.Path(sys.argv[1])
    payload = path.read_bytes()

    # Minifier-generated identifiers change between upstream releases.
    identifier = rb"[A-Za-z_$][A-Za-z0-9_$]*"
    release_guard = re.compile(
        rb"if\((" + identifier + rb")\.startsWith\("
        + identifier + rb"\+" + identifier + rb"\.sep\)\)\{"
    )
    guards = list(release_guard.finditer(payload))
    if len(guards) != 1:
        raise RuntimeError("unexpected release path guard count")
    guard = guards[0]
    old_release_guard = guard.group(0)
    new_release_guard = b"if(" + guard.group(1) + b"){"
    new_release_guard += b";" * (len(old_release_guard) - len(new_release_guard))
    if len(old_release_guard) != len(new_release_guard):
        raise RuntimeError("release path patch changed payload length")
    payload = payload.replace(old_release_guard, new_release_guard)

    old_auto_update = (
        b'{name:"auto-update",type:"boolean",description:"Auto-update on '
        b'launch (use --no-auto-update to disable)",default:!0}'
    )
    new_auto_update = old_auto_update[:-2] + b"1}"
    if payload.count(old_auto_update) != 1:
        raise RuntimeError("unexpected root auto-update option count")
    if len(old_auto_update) != len(new_auto_update):
        raise RuntimeError("auto-update patch changed payload length")
    payload = payload.replace(old_auto_update, new_auto_update)

    path.write_bytes(payload)
    PY

    ${lib.optionalString stdenv.hostPlatform.isDarwin ''
      # The upstream rg links against Homebrew's pcre2. Use Nix's closure instead.
      rm "$releaseDir/rg"
      ln -s ${lib.getExe ripgrep} "$releaseDir/rg"
      ${lib.getExe rcodesign} sign --code-signature-flags linker-signed "$releaseDir/cortex"
    ''}

    ${lib.optionalString stdenv.hostPlatform.isLinux ''
      seccompDir="$releaseDir/vendor/seccomp/${seccompArch}"
      install -Dm444 ${sandboxRuntimeSrc}/vendor/seccomp/${seccompArch}/unix-block.bpf \
        "$seccompDir/unix-block.bpf"
      install -Dm755 ${sandboxRuntimeSrc}/vendor/seccomp/${seccompArch}/apply-seccomp \
        "$seccompDir/apply-seccomp"

      # formatelf handles the bundle, while wrapBuddy preserves the embedded payload.
      wrapBuddy --no-recurse "$releaseDir/cortex"
    ''}

    # The sandbox resolves rg through PATH on both Linux and Darwin.
    # Expose the release's ripgrep without its other private helpers.
    mkdir -p $out/libexec/coco-runtime
    ln -s "$releaseDir/rg" $out/libexec/coco-runtime/rg

    # CoCo probes for the optional cocobox VM helper during cleanup. GNU which
    # reports a missing command on stderr, so silence only that exact lookup.
    # Prefer Nix-provided runtime tools, except bwrap: a host-provided bwrap may
    # carry the setuid wrapper or AppArmor policy required by the host OS.
    makeWrapper "$releaseDir/cortex" $out/bin/cortex \
      --prefix PATH : ${commonRuntimePath}:$out/libexec/coco-runtime${lib.optionalString stdenv.hostPlatform.isLinux ":${linuxExternalRuntimePath}"} \
      ${lib.optionalString stdenv.hostPlatform.isLinux "--suffix PATH : ${linuxBubblewrapPath}"} \
      --set OPENSSL_BIN ${lib.getExe openssl} \
      --run ${lib.escapeShellArg runtimeInit}

    runHook postInstall
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [
    versionCheckHook
    versionCheckHomeHook
  ];
  preVersionCheck = ''
    version=${displayVersion}
  '';
  installCheckPhase = ''
    runHook preInstallCheck

    checkHome=$(mktemp -d)
    export HOME="$checkHome"
    export XDG_CACHE_HOME="$checkHome/cache"

    # All first launches must succeed against the same uninitialized cache.
    launchPids=()
    for launch in 1 2 3 4; do
      $out/bin/cortex --version >"$checkHome/version-$launch.log" 2>&1 &
      launchPids+=("$!")
    done
    launchFailed=0
    for pid in "''${launchPids[@]}"; do
      wait "$pid" || launchFailed=1
    done
    cat "$checkHome"/version-*.log
    test "$launchFailed" -eq 0
    for launch in 1 2 3 4; do
      test "$(cat "$checkHome/version-$launch.log")" = 'Cortex Code v${displayVersion}'
    done

    banner=$($out/bin/cortex --version)
    printf '%s\n' "$banner"
    test "$banner" = 'Cortex Code v${displayVersion}'

    $out/bin/cortex connections list >/dev/null
    $out/bin/cortex completion generate --shell bash | grep -Fq '_cortex_completion'
    $out/bin/cortex mcp list >/dev/null
    $out/bin/cortex --help | grep -A2 -- '--auto-update' | grep -Fq '[default: false]'
    ! grep -Fq -- '--no-auto-update' $out/bin/cortex

    nodeMajor=$(${lib.getExe nodejs_22} -p 'Number(process.versions.node.split(".")[0])')
    test "$nodeMajor" -ge 22
    ${lib.getExe openssl} version | grep -q '^OpenSSL 3\.'
    grep -Fq '${nodejs_22}/bin' $out/bin/cortex
    grep -Fq '${openssl}/bin' $out/bin/cortex
    grep -Fq "$out/libexec/coco-runtime" $out/bin/cortex
    test -x $out/libexec/coco-runtime/rg
    $out/libexec/coco-runtime/rg --version | grep -q '^ripgrep '

    fipsStatus=$($out/bin/cortex --fips-status)
    printf '%s\n' "$fipsStatus"
    grep -Fq 'FIPS 140 mode: disabled' <<< "$fipsStatus"

    # Exercise FIPS initialization only where upstream ships its provider.
    if [ -d ${releaseDir}/openssl ]; then
      fipsStatus=$($out/bin/cortex --enable-fips --fips-status)
      printf '%s\n' "$fipsStatus"
      grep -Fq 'FIPS 140 mode: ENABLED' <<< "$fipsStatus"
      test -f "$HOME/.snowflake/cortex/fips/fipsmodule.cnf"
      storeName="''${releaseDir#/nix/store/}"
      storeName="''${storeName%%/*}"
      stagedOpenSSL="$XDG_CACHE_HOME/cortex-code/nix/$storeName/openssl"
      test -w "$stagedOpenSSL/openssl.cnf"
    fi

    ${lib.optionalString stdenv.hostPlatform.isLinux ''
      cocoboxOutput=
      if cocoboxOutput=$(${whichShim}/bin/which cocobox 2>&1); then
        echo "expected a missing cocobox lookup to fail" >&2
        exit 1
      fi
      test -z "$cocoboxOutput"

      cocoboxDir=$(mktemp -d)
      ln -s ${stdenv.shell} "$cocoboxDir/cocobox"
      test "$(PATH="$cocoboxDir" ${whichShim}/bin/which cocobox)" = "$cocoboxDir/cocobox"

      grep -Fq '${whichShim}/bin' $out/bin/cortex
      grep -Fq '${socat}/bin' $out/bin/cortex
      grep -Fq '${bubblewrap}/bin' $out/bin/cortex

      seccompDir=${releaseDir}/vendor/seccomp/${seccompArch}
      test -r "$seccompDir/unix-block.bpf"
      test -x "$seccompDir/apply-seccomp"
      if "$seccompDir/apply-seccomp" "$seccompDir/unix-block.bpf" ${stdenv.shell} -c \
        "${lib.getExe socat} UNIX-LISTEN:$checkHome/seccomp.sock - 2>/dev/null"; then
        echo "seccomp filter unexpectedly allowed an AF_UNIX socket" >&2
        exit 1
      fi
    ''}

    runHook postInstallCheck
  '';

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
    description = "Snowflake CoCo CLI, an AI coding agent for Snowflake";
    homepage = "https://docs.snowflake.com/en/user-guide/cortex-code/cortex-code-cli";
    changelog = "https://docs.snowflake.com/en/user-guide/cortex-code/changelog";
    license = flake.lib.licenses.unfree;
    sourceProvenance = with sourceTypes; [ binaryNativeCode ];
    maintainers = with flake.lib.maintainers; [ frankzvitale ];
    platforms = source.platforms;
    mainProgram = "cortex";
  };
}
