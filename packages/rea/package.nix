{
  lib,
  flake,
  buildNpmPackage,
  fetchFromGitHub,
  fetchurl,
  nodejs_26,
  formatelf,
  makeWrapper,
  stdenv,
  procps,
  versionCheckHook,
  versionCheckHomeHook,
}:

let
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
buildNpmPackage (finalAttrs: {
  pname = "rea";
  version = "6.8.0";

  src = fetchFromGitHub {
    owner = "morluto";
    repo = "rea";
    tag = "rea-agents-${finalAttrs.version}";
    hash = "sha256-2ADn3U3lvUoB4tCEpzO0rMfYE4sis+5uBiEazcp0gpI=";
  };

  npmDepsHash = "sha256-3WPXD+qm5WVfrTEvepKwX5RZBfbLBcPB0uDmKIx4MR8=";
  nodejs = nodejs_26;
  # Version 1 works with the pinned lockfile and keeps its existing cache reusable.
  npmDepsFetcherVersion = 1;
  # Install the pinned Frida binding explicitly; its installer otherwise downloads
  # a prebuild outside npm's dependency cache during the sandboxed build.
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
    # npm installs both libc variants; only the glibc build can run on NixOS.
    find node_modules -type d -name '*-musl' -prune -exec rm -rf {} +
    autoPatchelf node_modules
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
  ];
  postInstallCheck = ''
    "$out/bin/rea" --help > /dev/null
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
    node ${./check-mcp.mjs} "$out/bin/rea"
  '';

  passthru.category = "Utilities";

  meta = {
    description = "Reverse engineering CLI and MCP server for agents";
    homepage = "https://github.com/morluto/rea";
    changelog = "https://github.com/morluto/rea/releases/tag/rea-agents-${finalAttrs.version}";
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
})
