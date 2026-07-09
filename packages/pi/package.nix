{
  lib,
  buildNpmPackage,
  bun,
  makeWrapper,
  nodejs,
  fetchurl,
  fd,
  ripgrep,
  runCommand,
  versionCheckHook,
  versionCheckHomeHook,
  runtime ? "node",
  pname ? "pi",
  description ? "A terminal-based coding agent with multi-model support",
  longDescription ? null,
}:

let
  isBunRuntime = runtime == "bun";
  versionData = lib.importJSON ./hashes.json;
  version = versionData.version;
  packageRoot = "$out/lib/node_modules/@earendil-works/pi-coding-agent";

  # Create a source with package-lock.json included
  srcWithLock = runCommand "pi-src-with-lock" { } ''
    mkdir -p $out
    tar -xzf ${
      fetchurl {
        url = "https://registry.npmjs.org/@earendil-works/pi-coding-agent/-/pi-coding-agent-${version}.tgz";
        hash = versionData.sourceHash;
      }
    } -C $out --strip-components=1
    rm -f $out/npm-shrinkwrap.json
    cp ${./package-lock.json} $out/package-lock.json
  '';
in
assert lib.assertOneOf "runtime" runtime [
  "node"
  "bun"
];
buildNpmPackage {
  npmDepsFetcherVersion = 2;
  inherit version;
  inherit pname;

  src = srcWithLock;

  npmDepsHash = versionData.npmDepsHash;
  makeCacheWritable = true;

  # The package from npm is already built
  dontNpmBuild = true;

  nativeBuildInputs = lib.optionals isBunRuntime [
    makeWrapper
  ];

  postInstall =
    if isBunRuntime then
      ''
        rm -f "$out/bin/pi" "$out/bin/.pi-wrapped" 2>/dev/null || true

        find "$out" -path "*/node_modules/.bin/*" -type f -delete 2>/dev/null || true
        find "$out" -path "*/node_modules/.bin" -type d -empty -delete 2>/dev/null || true

        makeWrapper ${lib.getExe bun} "$out/bin/pi" \
          --add-flags "${packageRoot}/dist/bun/cli.js" \
          --prefix PATH : ${
            lib.makeBinPath [
              fd
              ripgrep
            ]
          } \
          --set PI_PACKAGE_DIR ${packageRoot} \
          --set PI_SKIP_VERSION_CHECK 1 \
          --set PI_TELEMETRY 0
      ''
    else
      ''
        wrapProgram $out/bin/pi \
          --prefix PATH : ${
            lib.makeBinPath [
              fd
              ripgrep
            ]
          } \
          --set PI_PACKAGE_DIR ${packageRoot} \
          --set PI_SKIP_VERSION_CHECK 1 \
          --set PI_TELEMETRY 0
      '';

  postFixup = lib.optionalString isBunRuntime ''
    while IFS= read -r script; do
      sed -i "1s|^#!${lib.getExe nodejs}$|#!${lib.getExe bun}|" "$script"
    done < <(find "$out" -type f -perm -0100 -exec grep -l "^#!${lib.getExe nodejs}$" {} +)
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [
    versionCheckHook
    versionCheckHomeHook
  ];

  passthru.category = "AI Coding Agents";
  passthru.skipUpdate = isBunRuntime;

  meta = {
    inherit description;
    homepage = "https://github.com/earendil-works/pi";
    changelog = "https://github.com/earendil-works/pi/releases";
    license = lib.licenses.mit;
    sourceProvenance = with lib.sourceTypes; [ binaryBytecode ];
    maintainers = with lib.maintainers; [ aos ];
    platforms = if isBunRuntime then bun.meta.platforms else lib.platforms.all;
    mainProgram = "pi";
  }
  // lib.optionalAttrs (longDescription != null) {
    inherit longDescription;
  };
}
