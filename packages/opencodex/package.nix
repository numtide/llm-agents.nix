{
  lib,
  flake,
  stdenvNoCC,
  fetchurl,
  makeWrapper,
  bun,
  nix-update-script,
  versionCheckHook,
  versionCheckHomeHook,
}:

let
  pname = "opencodex";
  version = "2.49.0";

  # The npm tarball published to the registry is the source of truth. Its URL
  # embeds `${version}`, so nix-update's npm version fetcher (keyed on the
  # registry.npmjs.org host) detects new releases and rewrites both the version
  # and this URL in one pass.
  src = fetchurl {
    url = "https://registry.npmjs.org/@bitkyc08/opencodex/-/opencodex-${version}.tgz";
    hash = "sha256-Uw2Ln55okh8vXUdqk7Rk+h5APcNgULuqCnvtNMmNlp8=";
  };

  # The npm tarball omits its lockfile, so fetch the release-matching one from
  # the upstream tag. This pins the resolved dependency tree. The URL embeds
  # `${version}`, so it tracks the version update automatically; only its hash
  # needs refreshing via `--subpackage=bunLock`.
  #
  # This is wrapped in a (trivial) fixed-output derivation rather than a bare
  # `fetchurl` so that the derivation exposes a `src` attribute: nix-update
  # locates a package's file via `builtins.unsafeGetAttrPos "src"`, which for a
  # bare `fetchurl` falls back to `meta.position` and resolves to nixpkgs'
  # read-only `fetchurl/default.nix`. The wrapper keeps the position here.
  bunLock = stdenvNoCC.mkDerivation {
    name = "${pname}-${version}-bun-lock";
    inherit version;
    src = fetchurl {
      url = "https://raw.githubusercontent.com/lidge-jun/opencodex/v${version}/bun.lock";
      hash = "sha256-nhFFbshRAn9dWbBYLyBaaZ9h+yTfx5Vdd6YXHnQYn3U=";
    };

    dontBuild = true;
    dontUnpack = true;

    installPhase = ''
      runHook preInstall
      cp "$src" "$out"
      runHook postInstall
    '';

    outputHashMode = "flat";
    outputHash = "sha256-nhFFbshRAn9dWbBYLyBaaZ9h+yTfx5Vdd6YXHnQYn3U=";
  };

  bunDepsHashes = {
    x86_64-linux = "sha256-LK48ufjA4nJwtwL5LXxe961bjvYXth7pAuD+7L+A4nc=";
    aarch64-linux = "sha256-O79FTF5E6xaMVbAJdtC9IiAaxUR4y88E5RSlB8Cn7zo=";
    aarch64-darwin = "sha256-V2+NRv53/7eLp0Um7XUoCZ3WyYoQWIaq/6Np6ysqYzw=";
  };

  # Fixed-output derivation that captures the bun-installed node_modules tree.
  # Hermetic and cached by hash, so the main derivation never touches the
  # network. Contains platform-specific native modules (e.g. @napi-rs/keyring),
  # so the hash varies by platform.
  bunDeps = stdenvNoCC.mkDerivation {
    name = "${pname}-${version}-bun-deps";
    inherit version src;
    sourceRoot = "package";

    nativeBuildInputs = [ bun ];

    postPatch = ''
      cp "${bunLock}" bun.lock
    '';

    buildPhase = ''
      runHook preBuild

      export HOME="$TMPDIR/home"
      export XDG_CACHE_HOME="$TMPDIR/cache"
      mkdir -p "$HOME" "$XDG_CACHE_HOME"

      # Nix supplies Bun at runtime; --ignore-scripts skips the npm `bun`
      # package's postinstall, which downloads another platform binary.
      bun install --frozen-lockfile --production --backend=copyfile --ignore-scripts

      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall

      # The Nix wrapper supplies Bun, so do not retain upstream's unused npm
      # copy of the Bun runtime or Bun's install cache.
      rm -rf node_modules/.cache node_modules/bun node_modules/@oven
      rm -f node_modules/.bin/bun node_modules/.bin/bunx

      mkdir -p "$out"
      cp -r node_modules "$out/node_modules"

      runHook postInstall
    '';

    outputHashMode = "recursive";
    outputHash =
      bunDepsHashes.${stdenvNoCC.hostPlatform.system}
        or (throw "Unsupported platform for opencodex: ${stdenvNoCC.hostPlatform.system}");
  };
in
stdenvNoCC.mkDerivation (finalAttrs: {
  inherit pname version src;

  sourceRoot = "package";

  nativeBuildInputs = [ makeWrapper ];

  dontBuild = true;

  installPhase = ''
    runHook preInstall

    package_out="$out/lib/opencodex"
    mkdir -p "$package_out"
    cp -r bin gui src package.json "$package_out/"
    cp -r "${bunDeps}/node_modules" "$package_out/node_modules"

    # makeWrapper joins <interpreter> <args...>, so the script path is
    # itself an argument and must come after any prefix flags.
    makeWrapper ${lib.getExe bun} "$out/bin/ocx" \
      --add-flags "$package_out/src/cli/index.ts"

    ln -s ocx "$out/bin/opencodex"

    runHook postInstall
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [
    versionCheckHook
    versionCheckHomeHook
  ];
  versionCheckProgramArg = [ "--version" ];

  passthru = {
    category = "Utilities";
    inherit bunDeps bunLock;

    # nix-update detects the version from the npm registry URL in `src`. After
    # the version is rewritten, the fixed-output `bunLock` subpackage must have
    # its hash recomputed. `bunDeps` contains platform-dependent optional
    # dependencies that are refreshed per architecture.
    updateScript = nix-update-script {
      extraArgs = [
        "--subpackage=bunLock"
      ];
    };
  };

  meta = {
    description = "Universal provider proxy for OpenAI Codex, Claude Code, Claude Desktop & Grok Build";
    homepage = "https://github.com/lidge-jun/opencodex";
    changelog = "https://github.com/lidge-jun/opencodex/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.mit;
    mainProgram = "ocx";
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
    platforms = lib.platforms.unix;
    maintainers = with flake.lib.maintainers; [ bet4it ];
  };
})
