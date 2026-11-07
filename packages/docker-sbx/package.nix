{
  lib,
  flake,
  platformSource,
  stdenvNoCC,
  installShellFiles,
  formatelf,
  makeBinaryWrapper,
  gccForLibs,
  e2fsprogs,
  lz4,
  xxhash,
  zlib,
  zstd,
  versionCheckHook,
  mkUpdater,
}:
let
  inherit (stdenvNoCC.hostPlatform) isLinux;
  source = platformSource {
    hashesFile = ./hashes.json;
    platforms = {
      x86_64-linux = "linux-amd64";
      aarch64-linux = "linux-arm64";
      aarch64-darwin = "darwin";
    };
    urlTemplate = "https://github.com/docker/sbx-releases/releases/download/v{version}/DockerSandboxes-{platform}.tar.gz";
  };
in
stdenvNoCC.mkDerivation {
  pname = "docker-sbx";
  inherit (source) version src;

  strictDeps = true;
  __structuredAttrs = true;

  # The darwin tarball has no top-level directory.
  sourceRoot = lib.optionalString (!isLinux) ".";

  # Preserve the upstream code signature; fixup could modify sealed files.
  dontFixup = !isLinux;

  nativeBuildInputs = [
    installShellFiles
  ]
  ++ lib.optionals isLinux [
    formatelf
    makeBinaryWrapper
  ];

  # mkfs.erofs and libsailor.so are dynamically linked.
  buildInputs = lib.optionals isLinux [
    gccForLibs
    lz4
    xxhash
    zlib
    zstd
  ];

  # The linux install.sh refuses to run without mkfs.ext4 on PATH and touches
  # /etc/apparmor.d, so lay out <prefix>/{bin,libexec} ourselves. The darwin
  # tarball ships Sbx.app plus bin/ symlinks into it; sbx finds its helpers
  # relative to its resolved path, so keep the bundle intact.
  installPhase = ''
    runHook preInstall
  ''
  + lib.optionalString isLinux ''
    install -Dm755 -t $out/bin sbx
    install -Dm755 -t $out/libexec containerd-shim-nerdbox-* docker-docklet mkfs.erofs
    install -Dm644 -t $out/libexec nerdbox-kernel-* nerdbox-rootfs-*.erofs sailor-rootfs-*.erofs
    install -Dm755 -t $out/libexec/lib libsailor.so
    wrapProgram $out/bin/sbx --prefix PATH : ${lib.makeBinPath [ e2fsprogs ]}
  ''
  + lib.optionalString (!isLinux) ''
    # Nix fails to clear flags on any store path named *.app, so install the
    # bundle under a plain name; sbx locates its helpers relative to itself.
    mkdir -p $out/libexec $out/bin
    cp -a Sbx.app $out/libexec/docker-sbx
    ln -s $out/libexec/docker-sbx/Contents/MacOS/sbx $out/bin/sbx
    ln -s $out/libexec/docker-sbx/Contents/MacOS/llmman $out/bin/llmman
    installShellCompletion \
      --bash --name sbx.bash Sbx.app/Contents/Resources/completions/bash/sbx \
      --zsh --name _sbx Sbx.app/Contents/Resources/completions/zsh/_sbx \
      --fish --name sbx.fish Sbx.app/Contents/Resources/completions/fish/sbx.fish
  ''
  + ''
    runHook postInstall
  '';

  # sbx writes state under $HOME even for `completion` and `version`.
  postInstall =
    lib.optionalString (isLinux && stdenvNoCC.buildPlatform.canExecute stdenvNoCC.hostPlatform)
      ''
        export HOME=$TMPDIR
        installShellCompletion --cmd sbx \
          --bash <($out/bin/sbx completion bash) \
          --zsh <($out/bin/sbx completion zsh) \
          --fish <($out/bin/sbx completion fish)
      '';

  nativeInstallCheckInputs = [ versionCheckHook ];
  doInstallCheck = true;
  versionCheckProgramArg = "version";
  versionCheckKeepEnvironment = [ "HOME" ];
  preVersionCheck = "export HOME=$TMPDIR";

  passthru.category = "Sandboxing & Isolation";
  passthru.updater = mkUpdater (
    source.updater
    // {
      versionSource = {
        type = "github";
        owner = "docker";
        repo = "sbx-releases";
      };
    }
  );

  meta = {
    description = "Docker Sandboxes: run coding agents in microVMs with controlled filesystem and network access";
    homepage = "https://docs.docker.com/ai/sandboxes/";
    changelog = "https://github.com/docker/sbx-releases/releases/tag/v${source.version}";
    mainProgram = "sbx";
    inherit (source) platforms;
    license = flake.lib.licenses.unfree;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    maintainers = [ lib.maintainers.skyesoss ];
  };
}
