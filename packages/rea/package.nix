{
  lib,
  flake,
  buildNpmPackage,
  fetchFromGitHub,
  fetchurl,
  nodejs,
  formatelf,
  makeWrapper,
  stdenv,
  procps,
  python3,
  versionCheckHook,
  versionCheckHomeHook,
  mkUpdater,
}:

let
  versionData = builtins.fromJSON (builtins.readFile ./hashes.json);
  inherit (versionData) version hash npmDepsHash;

  frida = lib.importJSON ./frida.json;
  fridaArch =
    {
      x86_64-linux = "x64";
      aarch64-linux = "arm64";
    }
    .${stdenv.hostPlatform.system};
  fridaBinding = fetchurl {
    url = "https://github.com/frida/frida/releases/download/${frida.version}/frida-v${frida.version}-napi-v${toString frida.napiVersion}-linux-${fridaArch}.tar.gz";
    hash = frida.hashes.${stdenv.hostPlatform.system};
  };
in
buildNpmPackage {
  pname = "rea";
  inherit version npmDepsHash;

  src = fetchFromGitHub {
    owner = "morluto";
    repo = "rea";
    tag = "rea-agents-${version}";
    inherit hash;
  };

  # Track nixpkgs' Node instead of a versioned alias so the package follows the
  # pin. Upstream's .nvmrc asks for Node 24.x, which `nodejs` currently is.
  nodejs = nodejs;
  npmDepsFetcherVersion = 2;
  # frida's install script downloads its binding; fetched separately below.
  npmFlags = [ "--ignore-scripts" ];
  env.HUSKY = "0";

  nativeBuildInputs = [
    formatelf
    makeWrapper
  ];
  buildInputs = [ stdenv.cc.cc.lib ];

  preBuild = ''
    test "$(node -p 'require("./node_modules/frida/package.json").version')" = "${frida.version}"
    tar -xzf ${fridaBinding} -C node_modules/frida
    # musl prebuilds would fail autoPatchelf
    find node_modules -type d -name '*-musl' -prune -exec rm -rf {} +
    autoPatchelf node_modules
    # Artifacts are still generated; only the comparison against the upstream
    # checkout's committed metadata is skipped.
    sed -i 's|"metadata:check": "node scripts/generate-package-metadata.mjs --check"|"metadata:check": "true"|' package.json
  '';

  postInstall = ''
    for command in rea rea-agents; do
      wrapProgram "$out/bin/$command" \
        --prefix PATH : ${lib.makeBinPath [ procps ]}
    done
  '';

  doInstallCheck = true;

  nativeInstallCheckInputs = [
    versionCheckHook
    versionCheckHomeHook
    python3
  ];

  postInstallCheck = ''
    # Loading this addon catches unresolved shared libraries and Node ABI drift.
    node -e 'require(process.argv[1])' \
      "$out/lib/node_modules/rea-agents/node_modules/@lydell/node-pty"
    node --input-type=module -e '
      const frida = await import(process.argv[1]);
      const device = await frida.getLocalDevice();
      const processes = await device.enumerateProcesses();
      if (!processes.some(p => p.pid === process.pid)) {
        throw new Error("Frida could not enumerate its own process");
      }
      console.log("Frida local device and process enumeration passed");
    ' "$out/lib/node_modules/rea-agents/node_modules/frida/build/src/frida.js"
    # The binary starting is not enough: the MCP server must answer the
    # handshake and advertise its tools.
    python3 ${./check_mcp.py} "$out/bin/rea"
  '';

  passthru.category = "Utilities";

  # frida.json is reconciled by update.py: it pins release assets keyed by the
  # npm version of `frida`, which no declarative kind can express.
  passthru.updater = mkUpdater {
    kind = "github-source";
    purl = "pkg:github/morluto/rea";
    depHashKey = "npmDepsHash";
    refPrefix = "rea-agents-";
  };

  meta = {
    description = "Reverse engineering CLI and MCP server for agents";
    homepage = "https://github.com/morluto/rea";
    changelog = "https://github.com/morluto/rea/releases/tag/rea-agents-${version}";
    license = lib.licenses.mit;
    sourceProvenance = with lib.sourceTypes; [
      fromSource
      binaryNativeCode
    ];
    maintainers = [ flake.lib.maintainers.silicalet ];
    mainProgram = "rea";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
  };
}
