{
  lib,
  flake,
  stdenvNoCC,
  callPackage,
  git,
  jxrlib,
  libheif,
  libreoffice,
  nodejs,
  pnpm_11,
  poppler-utils,
  chatgpt-runtime-source ? callPackage ./runtime-source.nix { },
  chatgpt-runtime-python ? callPackage ./runtime-python.nix {
    inherit chatgpt-runtime-source;
  },
}:

let
  runtimeMetadata = chatgpt-runtime-source.runtimeMetadata;
in
assert runtimeMetadata.nodeVersion == "v${nodejs.version}";
stdenvNoCC.mkDerivation {
  pname = "chatgpt-primary-runtime";
  inherit (runtimeMetadata) version;

  src = chatgpt-runtime-source;
  sourceRoot = "codex-primary-runtime";

  installPhase = ''
    runHook preInstall

    mkdir -p \
      "$out/dependencies/bin/fallback" \
      "$out/dependencies/bin/override" \
      "$out/dependencies/node/bin" \
      "$out/dependencies/python/bin"

    cp runtime.json "$out/runtime.json"
    cp -a plugins "$out/plugins"
    cp -a dependencies/node/node_modules "$out/dependencies/node/node_modules"

    ln -s ${lib.getExe nodejs} "$out/dependencies/node/bin/node"

    ln -s ${lib.getExe chatgpt-runtime-python} "$out/dependencies/python/bin/python3"
    ln -s python3 "$out/dependencies/python/bin/python"
    ln -s ${chatgpt-runtime-python.runtimePythonPackages}/lib "$out/dependencies/python/lib"

    ln -s ${lib.getExe' jxrlib "JxrDecApp"} "$out/dependencies/bin/override/JxrDecApp"
    ln -s ${lib.getExe' libheif "heif-dec"} "$out/dependencies/bin/override/heif-convert"
    ln -s ${lib.getExe' poppler-utils "pdfinfo"} "$out/dependencies/bin/override/pdfinfo"
    ln -s ${lib.getExe' poppler-utils "pdftoppm"} "$out/dependencies/bin/override/pdftoppm"
    ln -s ${lib.getExe' libreoffice "libreoffice"} "$out/dependencies/bin/override/soffice"

    ln -s ${lib.getExe git} "$out/dependencies/bin/fallback/git"
    ln -s ${lib.getExe pnpm_11} "$out/dependencies/bin/fallback/pnpm"

    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck

    test -x "$out/dependencies/node/bin/node"
    test -x "$out/dependencies/python/bin/python3"
    test -x "$out/dependencies/bin/override/JxrDecApp"
    test -x "$out/dependencies/bin/override/heif-convert"
    test -x "$out/dependencies/bin/override/pdfinfo"
    test -x "$out/dependencies/bin/override/pdftoppm"
    test -x "$out/dependencies/bin/override/soffice"
    test -x "$out/dependencies/bin/fallback/git"
    test -x "$out/dependencies/bin/fallback/pnpm"
    test -d "$out/plugins/openai-primary-runtime"
    test ! -e "$out/dependencies/native"

    RUNTIME_ROOT="$out" \
      NODE_PATH="$out/dependencies/node/node_modules" \
      "$out/dependencies/node/bin/node" - <<'JS'
    const assert = require("node:assert");
    const metadata = require(process.env.RUNTIME_ROOT + "/runtime.json");

    assert.equal(metadata.bundleVersion, "${runtimeMetadata.version}");
    assert.equal(metadata.bundleFormatVersion, 2);
    assert.equal(process.version, metadata.nodeVersion);

    for (const moduleName of [
      "@oai/artifact-tool",
      "sharp",
      "@napi-rs/canvas",
    ]) {
      require(moduleName);
    }

    require(
      process.env.RUNTIME_ROOT
        + "/dependencies/node/node_modules/@oai/artifact-tool/node_modules/skia-canvas",
    );
    JS

    runHook postInstallCheck
  '';

  allowSubstitutes = false;
  preferLocalBuild = true;

  passthru = {
    python = chatgpt-runtime-python;
    runtimeSource = chatgpt-runtime-source;
  };

  meta = with lib; {
    description = "Nix-compatible ChatGPT primary workspace runtime";
    homepage = "https://chatgpt.com";
    license = flake.lib.licenses.unfree;
    sourceProvenance = with sourceTypes; [
      binaryBytecode
      binaryNativeCode
    ];
    platforms = chatgpt-runtime-source.meta.platforms;
  };
}
