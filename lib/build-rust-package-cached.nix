# buildRustPackage that compiles the crates.io/git dependencies in a
# derivation of their own, so a new release only rebuilds the workspace.
#
# `cargoDeps` additionally holds a stub of the workspace. Its hash is still
# `cargoHash`, but differs from the one buildRustPackage expects.
{
  lib,
  stdenvNoCC,
  rustPlatform,
  writers,
  python3Packages,
  zstd,
}:

let
  cargoSkeleton = writers.writePython3Bin "cargo-skeleton" {
    libraries = [ python3Packages.tomli-w ];
    doCheck = false;
  } (builtins.readFile ./cargo-skeleton.py);
in

{
  pname,
  src,
  cargoHash,
  sourceRoot ? "source",
  cargoPatches ? [ ],
  preBuild ? "",
  nativeBuildInputs ? [ ],
  ...
}@args:

let
  # Only borrowed for its tools; never built.
  upstream = rustPlatform.fetchCargoVendor {
    inherit src;
    hash = lib.fakeHash;
  };

  # No version in the name: the path must survive a release.
  cargoDeps = stdenvNoCC.mkDerivation {
    name = "${pname}-vendor";
    inherit src sourceRoot;
    patches = cargoPatches;
    nativeBuildInputs = [
      cargoSkeleton
    ]
    ++ upstream.nativeBuildInputs
    ++ upstream.vendorStaging.nativeBuildInputs;
    impureEnvVars = lib.fetchers.proxyImpureEnvVars;

    buildPhase = ''
      runHook preBuild
      fetch-cargo-vendor-util create-vendor-staging Cargo.lock "$TMPDIR/staging"
      fetch-cargo-vendor-util create-vendor "$TMPDIR/staging" "$out"
      cargo-skeleton lock Cargo.lock > "$out/Cargo.lock"
      # Hidden, so that cargo does not take it for a vendored crate.
      cargo-skeleton skeleton "$NIX_BUILD_TOP/${lib.head (lib.splitString "/" sourceRoot)}" "$out/.skeleton"
      runHook postBuild
    '';

    dontConfigure = true;
    dontInstall = true;
    dontFixup = true;
    strictDeps = true;

    outputHash = cargoHash;
    outputHashAlgo = if cargoHash == "" then "sha256" else null;
    outputHashMode = "recursive";
  };

  # Remap in both builds because cached dependency objects carry source
  # locations, and the shipped binaries must not retain the vendor tree.
  remapVendor = ''
    export NIX_RUSTFLAGS="''${NIX_RUSTFLAGS:+$NIX_RUSTFLAGS }--remap-path-prefix=${cargoDeps}/=vendor/"
  '';

  common = removeAttrs args [ "cargoHash" ] // {
    inherit sourceRoot;
    cargoPatches = [ ];
    # Without cargoVendorDir, cargoSetupHook copies the vendored crates into
    # the build directory. Their path ends up in cargo's fingerprints and the
    # build directory is random on darwin, so let the hook resolve this link
    # to the store path, which is the same in every build.
    cargoVendorDir = ".cargo-vendor";
    postUnpack = ''
      ln -s ${cargoDeps} "$sourceRoot/.cargo-vendor"
    ''
    + args.postUnpack or "";
  };

  cargoArtifacts = rustPlatform.buildRustPackage (
    common
    // {
      pname = "${pname}-deps";
      version = "0";
      src = null;
      unpackPhase = ''
        runHook preUnpack
        cp -r ${cargoDeps}/.skeleton ${lib.head (lib.splitString "/" sourceRoot)}
        chmod -R u+w .
        runHook postUnpack
      '';
      patches = [ ];
      prePatch = "";
      postPatch = "";
      env = removeAttrs (args.env or { }) [ "RUSTC_WRAPPER" ];
      preBuild = remapVendor + preBuild;
      nativeBuildInputs = nativeBuildInputs ++ [ zstd ];

      doCheck = false;
      doInstallCheck = false;
      dontFixup = true;
      outputs = [ "out" ];
      installPhase = ''
        runHook preInstall
        # The stubs must not pass for the real crates.
        while read -r member; do
          find target -path "*/.fingerprint/$member-*" -prune -exec rm -r {} +
        done < "$NIX_BUILD_TOP/${lib.head (lib.splitString "/" sourceRoot)}/members"
        mkdir -p "$out"
        tar -c --exclude incremental target | zstd -T"$NIX_BUILD_CORES" -o "$out/target.tar.zst"
        runHook postInstall
      '';
      postInstall = "";
      postFixup = "";
      passthru = { };
      meta = { };
    }
  );
in
rustPlatform.buildRustPackage (
  common
  // {
    disallowedReferences = (args.disallowedReferences or [ ]) ++ [
      cargoDeps
      cargoArtifacts
    ];

    nativeBuildInputs = nativeBuildInputs ++ [
      cargoSkeleton
      zstd
    ];

    # cargoVendorDir turns off cargoSetupHook's lock file check.
    postPatch = ''
      if ! cargo-skeleton lock Cargo.lock | diff - ${cargoDeps}/Cargo.lock; then
        echo "ERROR: cargoHash is out of date" >&2
        exit 1
      fi
    ''
    + args.postPatch or "";

    preBuild =
      remapVendor
      + ''
        zstd -d < ${cargoArtifacts}/target.tar.zst | tar -x
      ''
      + preBuild;

    passthru = (args.passthru or { }) // {
      inherit cargoArtifacts;
    };
  }
)
