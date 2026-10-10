{
  lib,
  stdenv,
  bun2nixLib,
  bun,
  fetchFromGitHub,
  makeWrapper,
  jq,
}:

let
  versionData = builtins.fromJSON (builtins.readFile ./hashes.json);
  inherit (versionData) version hash;
in
stdenv.mkDerivation {
  pname = "collie";
  inherit version;

  src = fetchFromGitHub {
    owner = "AltanS";
    repo = "collie";
    tag = "v${version}";
    inherit hash;
  };

  nativeBuildInputs = [
    bun2nixLib.hook
    bun
    makeWrapper
  ];

  # Two lockfiles: the root bridge (Bun server) and the Vite/React web UI.
  # combined-bun.nix merges both so one cache serves both installs.
  bunDeps = bun2nixLib.fetchBunDeps {
    bunNix = ./combined-bun.nix;
  };

  dontUseBunBuild = true;
  dontUseBunInstall = true;
  dontRunLifecycleScripts = true;

  # "@types/bun": "latest" makes bun hit the registry even with a full
  # cache.  Pin it to the version the lockfile already resolved.
  postPatch = ''
    typesBun=$(sed -n 's/.*"@types\/bun@\([0-9][0-9.]*\)".*/\1/p' bun.lock | head -1)
    ${lib.getExe jq} --arg v "$typesBun" '.devDependencies."@types/bun" = $v' \
      package.json > package.json.tmp && mv package.json.tmp package.json
    sed -i 's/"@types\/bun": "latest"/"@types\/bun": "'"$typesBun"'"/' bun.lock

    # The build id bakes in the wall clock; pin it so builds reproduce.
    substituteInPlace web/vite.config.ts \
      --replace-fail 'const buildTime = new Date().toISOString();' \
        'const buildTime = new Date(Number(process.env.SOURCE_DATE_EPOCH ?? 0) * 1000).toISOString();'
  '';

  buildPhase = ''
    runHook preBuild

    # Hoisted linker (not the hook's isolated one): vite-plugin-pwa's virtual
    # module resolves its transitive workbox-window from the project root,
    # which the isolated layout doesn't expose.  Hardlink backend: Darwin's
    # default clonefile clones the store cache's read-only dir perms and the
    # install falls over; hardlink creates fresh dirs and links only files.
    pushd web
    bun install --frozen-lockfile --no-progress --ignore-scripts \
      --backend=hardlink
    bun run build
    popd

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    # Only web-push (optional, for push notifications) is needed at runtime;
    # typescript and the type stubs are dev-only and dominate the closure.
    rm -rf node_modules/.bin node_modules/@types node_modules/typescript \
      node_modules/.bun/@types+*@* node_modules/.bun/typescript@* \
      node_modules/.bun/bun-types@*
    find node_modules -xtype l -delete

    mkdir -p $out/lib/collie
    cp -r bridge cli docs scripts systemd node_modules package.json herdr-plugin.toml \
      $out/lib/collie/
    mkdir -p $out/lib/collie/web
    cp -r web/dist $out/lib/collie/web/dist
    cp -r web/src $out/lib/collie/web/src

    makeWrapper ${lib.getExe bun} $out/bin/collie \
      --add-flags "run $out/lib/collie/bridge/index.ts"

    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    test -f $out/lib/collie/web/dist/index.html
    test -f $out/lib/collie/web/dist/build-info.json
    runHook postInstallCheck
  '';

  passthru.category = "Workflow & Project Management";

  meta = with lib; {
    description = "Mobile web UI to monitor and reply to your Herdr agent herd over Tailscale";
    homepage = "https://github.com/AltanS/collie";
    changelog = "https://github.com/AltanS/collie/releases/tag/v${version}";
    license = licenses.mit;
    sourceProvenance = with sourceTypes; [ fromSource ];
    maintainers = with maintainers; [ zimbatm ];
    mainProgram = "collie";
    platforms = platforms.unix;
  };
}
