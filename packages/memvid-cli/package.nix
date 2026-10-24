{
  lib,
  flake,
  stdenv,
  fetchzip,
  makeWrapper,
  formatelf,
  libx11,
  libxext,
  libxi,
  libxrender,
  libxtst,
  openssl,
  zlib,
  alsa-lib,
}:

let
  srcAttrs =
    if stdenv.isAArch64 then
      {
        url = "https://registry.npmjs.org/@memvid/cli-linux-arm64/-/cli-linux-arm64-2.0.160.tgz";
        # FIXME: placeholder — replace with the real fetchzip (unpacked tree) hash
        hash = lib.fakeHash;
      }
    else
      {
        url = "https://registry.npmjs.org/@memvid/cli-linux-x64/-/cli-linux-x64-2.0.160.tgz";
        hash = "sha256-we0KZzKrYRATJElP9OkR4hERQ5S+Zb9qFDCO3WJtV/I=";
      };
in
stdenv.mkDerivation rec {
  pname = "memvid-cli";
  version = "2.0.160";

  src = fetchzip srcAttrs;

  nativeBuildInputs = [
    formatelf
    makeWrapper
  ];

  buildInputs = [
    alsa-lib
    libx11
    libxext
    libxi
    libxrender
    libxtst
    openssl
    stdenv.cc.cc.lib
    zlib
  ];

  installPhase = ''
    runHook preInstall

    install -d $out/libexec/memvid-cli
    cp -R $src/. $out/libexec/memvid-cli/
    chmod -R u+w $out/libexec/memvid-cli
    chmod 755 $out/libexec/memvid-cli/memvid

    makeWrapper $out/libexec/memvid-cli/memvid $out/bin/memvid \
      --prefix LD_LIBRARY_PATH : "$out/libexec/memvid-cli"

    runHook postInstall
  '';

  doInstallCheck = true;

  # No versionCheckHook: --version prints the bundled memvid-core version,
  # not the npm package version.
  installCheckPhase = ''
    runHook preInstallCheck

    tmp_home=$(mktemp -d)
    tmp_cache=$(mktemp -d)
    HOME="$tmp_home" XDG_CACHE_HOME="$tmp_cache" $out/bin/memvid --help > /dev/null

    runHook postInstallCheck
  '';

  passthru.category = "Memory & Code Intelligence";

  meta = with lib; {
    description = "AI memory CLI - crash-safe, single-file storage with semantic search";
    homepage = "https://memvid.com";
    changelog = "https://github.com/memvid/memvid/releases";
    license = licenses.asl20;
    # CLI is closed-source; upstream repo only contains the memvid-core library.
    sourceProvenance = with sourceTypes; [
      binaryNativeCode
    ];
    maintainers = with flake.lib.maintainers; [ smdex ];
    mainProgram = "memvid";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
  };
}
