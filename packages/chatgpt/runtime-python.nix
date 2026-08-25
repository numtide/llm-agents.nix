{
  lib,
  flake,
  stdenv,
  stdenvNoCC,
  callPackage,
  libxcrypt-legacy,
  makeWrapper,
  python312,
  wrapBuddy,
  zlib,
  chatgpt-runtime-source ? callPackage ./runtime-source.nix { },
}:

let
  runtimeMetadata = chatgpt-runtime-source.runtimeMetadata;
  runtimeLibraryPath = lib.makeLibraryPath [
    libxcrypt-legacy
    zlib
    stdenv.cc.cc.lib
  ];

  runtimePythonPackages = python312.pkgs.toPythonModule (
    stdenv.mkDerivation {
      pname = "chatgpt-primary-runtime-python-packages";
      inherit (runtimeMetadata) version;

      src = chatgpt-runtime-source;
      sourceRoot = "codex-primary-runtime/dependencies/python/${python312.sitePackages}";

      nativeBuildInputs = [ wrapBuddy ];
      buildInputs = [
        libxcrypt-legacy
        zlib
        stdenv.cc.cc.lib
      ];

      # The module tree contains a Bun executable whose embedded payload is
      # corrupted by patchelf and strip. wrapBuddy supplies a compatible ELF
      # loader without modifying the executable itself.
      dontPatchELF = true;
      dontStrip = true;

      installPhase = ''
        runHook preInstall

        mkdir -p "$out/${python312.sitePackages}"
        cp -a . "$out/${python312.sitePackages}/"

        runHook postInstall
      '';
    }
  );

  pythonEnvironment = python312.withPackages (_: [ runtimePythonPackages ]);
in
assert
  lib.versions.majorMinor python312.version == lib.versions.majorMinor runtimeMetadata.pythonVersion;
stdenvNoCC.mkDerivation {
  pname = "chatgpt-primary-runtime-python";
  inherit (runtimeMetadata) version;

  dontUnpack = true;
  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/bin"
    makeWrapper ${pythonEnvironment}/bin/python3 "$out/bin/python3" \
      --prefix LD_LIBRARY_PATH : ${lib.escapeShellArg runtimeLibraryPath}
    ln -s python3 "$out/bin/python"
    ln -s python3 "$out/bin/python3.12"

    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck

    HOME="$TMPDIR" "$out/bin/python3" - <<'PY'
    import sys
    from pathlib import Path

    assert sys.version.startswith("${lib.versions.majorMinor runtimeMetadata.pythonVersion}")

    import artifact_tool_v2
    import cryptography
    import lxml.etree
    import numpy
    import pandas
    import PIL.Image
    import pydantic_core
    import pypdfium2
    import reportlab

    from artifact_tool_v2.rpc.daemon import start_daemon

    socket_path = start_daemon()
    assert Path(socket_path).exists()
    PY

    runHook postInstallCheck
  '';

  allowSubstitutes = false;
  preferLocalBuild = true;

  passthru = {
    inherit pythonEnvironment runtimePythonPackages;
    runtimeSource = chatgpt-runtime-source;
  };

  meta = with lib; {
    description = "Python environment for ChatGPT's primary workspace runtime";
    homepage = "https://chatgpt.com";
    license = flake.lib.licenses.unfree;
    sourceProvenance = with sourceTypes; [ binaryNativeCode ];
    platforms = chatgpt-runtime-source.meta.platforms;
    mainProgram = "python3";
  };
}
