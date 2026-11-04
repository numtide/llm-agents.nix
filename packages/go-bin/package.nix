{
  lib,
  stdenv,
  fetchurl,
}:

let
  versionData = builtins.fromJSON (builtins.readFile ./hashes.json);
  inherit (versionData) version hashes;

  platform = with stdenv.hostPlatform.go; "${GOOS}-${if GOARCH == "arm" then "armv6l" else GOARCH}";
in
stdenv.mkDerivation {
  pname = "go-bin";
  inherit version;

  src = fetchurl {
    url = "https://go.dev/dl/go${version}.${platform}.tar.gz";
    hash = hashes.${platform} or (throw "Missing Go hash for platform ${platform}");
  };

  # Preserve code signature on Darwin
  dontStrip = stdenv.hostPlatform.isDarwin;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/share/go $out/bin
    cp -r . $out/share/go
    ln -s $out/share/go/bin/go $out/bin/go
    ln -s $out/share/go/bin/gofmt $out/bin/gofmt
    runHook postInstall
  '';

  # buildGoModule reads these attributes from the `go` package.
  inherit (stdenv.hostPlatform.go) GOOS GOARCH;
  CGO_ENABLED = 1;

  passthru = {
    hideFromDocs = true;
  };

  meta = {
    description = "Latest Go toolchain (prebuilt binary) for building packages that need a newer patch release than nixpkgs ships";
    homepage = "https://go.dev/";
    license = lib.licenses.bsd3;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    platforms = lib.platforms.darwin ++ lib.platforms.linux;
  };
}
