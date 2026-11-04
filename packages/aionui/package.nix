{
  lib,
  flake,
  stdenv,
  bun2nixLib,
  bun,
  nodejs,
  python3,
  electron_43,
  fetchFromGitHub,
  fetchpatch,
  runCommand,
  makeWrapper,
  glib,
  libsecret,
}:

let
  electron = electron_43;
  versionData = builtins.fromJSON (builtins.readFile ./hashes.json);
  inherit (versionData) version hash;

  extraDependencies = builtins.toJSON {
    "@codemirror/commands" = "6.10.3";
    "@codemirror/lang-html" = "6.4.11";
    "@codemirror/view" = "6.41.0";
    "@xmldom/xmldom" = "0.9.9";
    "beautiful-mermaid" = "1.1.3";
    dayjs = "1.11.20";
    "https-proxy-agent" = "9.0.0";
    jszip = "3.10.1";
    "png-chunk-text" = "1.0.0";
    "png-chunks-extract" = "1.0.0";
    "tree-sitter-bash" = "0.25.1";
    yauzl = "3.3.0";
  };

  src = fetchFromGitHub {
    owner = "iOfficeAI";
    repo = "AionUi";
    tag = "v${version}";
    inherit hash;
  };

  runtimeKey =
    if stdenv.hostPlatform.isLinux && stdenv.hostPlatform.isx86_64 then
      "linux-x64"
    else if stdenv.hostPlatform.isLinux && stdenv.hostPlatform.isAarch64 then
      "linux-arm64"
    else
      throw "Unsupported platform for aionui: ${stdenv.hostPlatform.system}";
in
stdenv.mkDerivation {
  pname = "aionui";
  inherit version;

  inherit src;

  nativeBuildInputs = [
    bun2nixLib.hook
    bun
    nodejs
    python3
    makeWrapper
  ];

  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [
    stdenv.cc.cc.lib
    glib
    libsecret
  ];

  bunDeps = bun2nixLib.fetchBunDeps {
    # bun.nix references workspace packages via relative paths that only
    # exist in the upstream monorepo, so remap them onto the fetched src.
    bunNix =
      { fetchurl, ... }:
      import ./bun.nix {
        inherit fetchurl;
        copyPathToStore =
          path:
          let
            rel = lib.removePrefix (toString ./. + "/") (toString path);
          in
          runCommand "aionui-workspace-${baseNameOf rel}" { } ''
            cp -r ${src}/${rel} $out
          '';
      };
  };

  dontRunLifecycleScripts = true;
  dontUseBunBuild = true;
  dontUseBunInstall = true;
  dontStrip = true;

  postPatch = ''
    cp ${./bun.lock} bun.lock
    node -e "const fs=require('fs'); const pkg=JSON.parse(fs.readFileSync('package.json','utf8')); pkg.dependencies={...(pkg.dependencies||{}), ...JSON.parse(process.argv[1])}; fs.writeFileSync('package.json', JSON.stringify(pkg, null, 2) + '\n');" '${extraDependencies}'
  '';

  env = {
    ELECTRON_SKIP_BINARY_DOWNLOAD = "1";
    AIONUI_DISABLE_AUTO_UPDATE = "1";
    AIONUI_CDP_PORT = "0";
  };

  buildPhase = ''
    runHook preBuild

    export HOME=$TMPDIR
    export npm_config_build_from_source=true
    export npm_config_runtime=electron
    export npm_config_target=${electron.version}
    export npm_config_nodedir=${electron.headers}
    export PYTHON=${python3}/bin/python3

    betterSqliteDir=$(echo node_modules/.bun/better-sqlite3@*/node_modules/better-sqlite3)
    nodeGyp=$PWD/$(echo node_modules/.bun/node-gyp@*/node_modules/node-gyp/bin/node-gyp.js)
    if [ -d "$betterSqliteDir" ]; then
      # better-sqlite3 < 12.11 vs. the V8 14.8 External API in electron >= 42
      patch -d "$betterSqliteDir" -p1 < ${
        fetchpatch {
          url = "https://github.com/WiseLibs/better-sqlite3/commit/5bb63a2f4c5aa34de2c292b983d2b6c4fcfc6f94.patch";
          hash = "sha256-Ln40MtZD7YSHhmBVagY0AJl7ZcPh9gaxC+TdMxPG57c=";
        }
      }
      (cd "$betterSqliteDir" && node "$nodeGyp" rebuild --release)
    fi

    # The desktop config also builds the MCP servers via a closeBundle plugin
    bunx electron-vite build --config packages/desktop/electron.vite.config.ts

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    electronDist=$out/libexec/aionui/electron-dist
    appRoot=$electronDist/resources/app
    bundledBunDir=$electronDist/resources/bundled-bun/${runtimeKey}

    mkdir -p $electronDist $appRoot $bundledBunDir $out/bin

    cp -r ${electron}/libexec/electron/. $electronDist/
    chmod -R u+w $electronDist

    rm -f $electronDist/resources/default_app.asar

    cp package.json $appRoot/
    cp -r node_modules $appRoot/
    cp -r out $appRoot/
    # node_modules contains symlinks into the workspace packages
    cp -r packages $appRoot/
    cp -r public $appRoot/
    cp -r resources $appRoot/

    if [ -d out/main/skills ]; then
      cp -r out/main/skills $appRoot/skills
      mkdir -p $appRoot/src/process/resources
      cp -r out/main/skills $appRoot/src/process/resources/skills
    fi
    if [ -d out/main/assistant ]; then
      cp -r out/main/assistant $appRoot/assistant
      mkdir -p $appRoot/src/process/resources
      cp -r out/main/assistant $appRoot/src/process/resources/assistant
    fi
    if [ -d out/main/static ]; then
      cp -r out/main/static $appRoot/static
    fi

    cp ${bun}/bin/bun $bundledBunDir/bun
    chmod +x $bundledBunDir/bun

    makeWrapper ${electron}/bin/electron $out/bin/aionui \
      --set ELECTRON_OVERRIDE_DIST_PATH "$electronDist" \
      --set ELECTRON_FORCE_IS_PACKAGED 1 \
      --set AIONUI_DISABLE_AUTO_UPDATE 1 \
      --set AIONUI_CDP_PORT 0 \
      --set NODE_ENV production \
      --prefix LD_LIBRARY_PATH : ${
        lib.makeLibraryPath [
          stdenv.cc.cc.lib
          glib
          libsecret
        ]
      } \
      --prefix PATH : ${
        lib.makeBinPath [
          bun
          nodejs
        ]
      } \
      --run "cd '$appRoot'" \
      --add-flags "--no-sandbox --disable-setuid-sandbox" \
      --add-flags "$appRoot"

    runHook postInstall
  '';

  passthru.category = "AI Assistants";

  meta = with lib; {
    description = "Desktop and WebUI cowork app that turns AI agents into a local assistant and server";
    homepage = "https://github.com/iOfficeAI/AionUi";
    changelog = "https://github.com/iOfficeAI/AionUi/releases/tag/v${version}";
    license = licenses.asl20;
    sourceProvenance = [ sourceTypes.fromSource ];
    maintainers = with flake.lib.maintainers; [ smdex ];
    mainProgram = "aionui";
    platforms = platforms.linux;
  };
}
