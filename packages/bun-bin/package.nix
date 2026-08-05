{
  lib,
  stdenvNoCC,
  fetchurl,
  autoPatchelfHook,
  unzip,
  installShellFiles,
  openssl,
  cctools,
  darwin,
  rcodesign,
}:

let
  versionData = builtins.fromJSON (builtins.readFile ./hashes.json);
  inherit (versionData) version hashes;

  # Release tag holding the artifacts. Normally "bun-v<version>"; the rolling
  # "canary" tag is used while a needed fix is merged upstream but unreleased.
  #
  # Currently pinned to canary for oven-sh/bun#31024 (merged 2026-07-29), the
  # ELF fix without which `bun build --compile` emits segfaulting binaries on
  # NixOS. The newest stable, 1.3.14, predates it. update.py drops `tag` and
  # returns to a stable tag as soon as bun 1.4.0 is released; note that the
  # canary artifacts are mutable, so the pinned hashes go stale on rotation.
  releaseTag = versionData.tag or "bun-v${version}";

  archName =
    {
      "aarch64-darwin" = "bun-darwin-aarch64";
      "aarch64-linux" = "bun-linux-aarch64";
      "x86_64-darwin" = "bun-darwin-x64-baseline";
      "x86_64-linux" = "bun-linux-x64";
    }
    .${stdenvNoCC.hostPlatform.system}
      or (throw "Unsupported platform for bun-bin: ${stdenvNoCC.hostPlatform.system}");
in
stdenvNoCC.mkDerivation {
  pname = "bun-bin";
  inherit version;

  src = fetchurl {
    url = "https://github.com/oven-sh/bun/releases/download/${releaseTag}/${archName}.zip";
    hash =
      hashes.${stdenvNoCC.hostPlatform.system}
        or (throw "Missing bun hash for ${stdenvNoCC.hostPlatform.system}");
  };

  # Darwin zips contain a subdirectory; Linux ones extract flat.
  sourceRoot =
    {
      "aarch64-darwin" = archName;
      "x86_64-darwin" = archName;
    }
    .${stdenvNoCC.hostPlatform.system} or null;

  strictDeps = true;

  # Deliberate exception to the repo-wide use-formatelf rule (see the ignore
  # entry in rules/use-formatelf.yml).
  #
  # `bun build --compile` copies the running bun binary as the template for
  # its output and appends a .bun section, so the template's segment layout
  # has to be one bun's own ELF writer understands. Measured on x86_64-linux:
  #
  #   bun         patcher      bun runs   compiled output runs
  #   1.3.13      patchelf     yes        yes    (status quo)
  #   1.3.14      patchelf     NO         -      (oven-sh/bun#31023)
  #   1.3.14      formatelf    yes        NO
  #   canary      patchelf     yes        yes
  #   canary      formatelf    yes        NO
  #
  # formatelf appends its extra writable PT_LOAD after the image instead of
  # prepending it; write_bun_section then lands .bun in a segment bun cannot
  # replay, and the output faults at execve even with the #31024 fix. Only
  # patchelf's layout produces a working binary here.
  nativeBuildInputs = [
    unzip
    installShellFiles
  ]
  ++ lib.optionals stdenvNoCC.hostPlatform.isLinux [ autoPatchelfHook ];

  buildInputs = [ openssl ];

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    install -Dm 755 ./bun $out/bin/bun
    ln -s $out/bin/bun $out/bin/bunx
    runHook postInstall
  '';

  postPhases = [ "postPatchelf" ];
  postPatchelf =
    lib.optionalString stdenvNoCC.hostPlatform.isDarwin ''
      '${lib.getExe' cctools "${cctools.targetPrefix}install_name_tool"}' $out/bin/bun \
        -change /usr/lib/libicucore.A.dylib '${lib.getLib darwin.ICU}/lib/libicucore.A.dylib'
      '${lib.getExe rcodesign}' sign --code-signature-flags linker-signed $out/bin/bun
    ''
    +
      lib.optionalString
        (
          stdenvNoCC.buildPlatform.canExecute stdenvNoCC.hostPlatform
          && !(stdenvNoCC.hostPlatform.isDarwin && stdenvNoCC.hostPlatform.isx86_64)
        )
        ''
          installShellCompletion --cmd bun \
            --bash <(SHELL="bash" $out/bin/bun completions) \
            --zsh <(SHELL="zsh" $out/bin/bun completions) \
            --fish <(SHELL="fish" $out/bin/bun completions)
        '';

  passthru.hideFromDocs = true;

  meta = {
    description = "Latest Bun runtime (prebuilt binary) for packages that need a newer version than nixpkgs ships";
    homepage = "https://bun.sh";
    changelog = "https://bun.sh/blog/bun-v${version}";
    license = with lib.licenses; [
      mit
      lgpl21Only
    ];
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    mainProgram = "bun";
    platforms = builtins.attrNames hashes;
    broken = stdenvNoCC.hostPlatform.isMusl;
  };
}
