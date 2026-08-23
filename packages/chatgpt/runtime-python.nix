{
  lib,
  flake,
  stdenv,
  fetchurl,
  libxcrypt-legacy,
  makeWrapper,
  wrapBuddy,
  zlib,
}:

let
  sourceData = builtins.fromJSON (builtins.readFile ./hashes.json);
  platform = stdenv.hostPlatform.system;
  source =
    sourceData.runtimeSources.${platform}
      or (throw "Unsupported ChatGPT primary runtime platform: ${platform}");
  runtimeLibraryPath = lib.makeLibraryPath [
    libxcrypt-legacy
    zlib
    stdenv.cc.cc.lib
  ];
in
stdenv.mkDerivation {
  pname = "chatgpt-primary-runtime-python";
  inherit (source) version;

  src = fetchurl {
    inherit (source) url hash;
  };

  sourceRoot = "codex-primary-runtime/dependencies/python";

  nativeBuildInputs = [
    makeWrapper
    wrapBuddy
  ];

  buildInputs = [
    libxcrypt-legacy
    zlib
    stdenv.cc.cc.lib
  ];

  # The runtime contains a Bun executable whose embedded payload is corrupted by
  # patchelf and strip. wrapBuddy supplies a compatible ELF loader without
  # modifying the executable itself.
  dontPatchELF = true;
  dontStrip = true;

  installPhase = ''
    runHook preInstall

    mkdir -p "$out"
    cp -a . "$out/"

    # Upstream's archive contains absolute symlinks into its temporary assembly
    # directory. Retarget them to the immutable runtime installed here.
    while IFS= read -r -d "" link; do
      target="$(readlink "$link")"
      case "$target" in
        /tmp/codex-primary-runtime-*/python-download/python/*)
          relative="''${target#*/python-download/python/}"
          ln -sfn "$out/$relative" "$link"
          ;;
        *)
          echo "unexpected dangling symlink in primary runtime: $link -> $target" >&2
          exit 1
          ;;
      esac
    done < <(find "$out" -xtype l -print0)

    # This malformed linker stub is unused by the bundled interpreter and
    # extensions; libpython3.12.so is the functional development symlink.
    rm "$out/lib/libpython3.so"

    wrapProgram "$out/bin/python3.12" \
      --prefix LD_LIBRARY_PATH : "$out/lib:${runtimeLibraryPath}"

    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck

    "$out/bin/python3" - <<'PY'
    import sys
    from pathlib import Path

    assert sys.version.startswith("${source.pythonVersion}")

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

  meta = with lib; {
    description = "Python environment bundled with ChatGPT's primary workspace runtime";
    homepage = "https://chatgpt.com";
    license = flake.lib.licenses.unfree;
    sourceProvenance = with sourceTypes; [ binaryNativeCode ];
    platforms = builtins.attrNames sourceData.runtimeSources;
    mainProgram = "python3";
  };
}
