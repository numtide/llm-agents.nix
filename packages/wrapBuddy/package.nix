{
  lib,
  stdenv,
  fetchFromGitHub,
  buildPackages,
  makeSetupHook,
  binutils,
  xxd,
  strace,
}:

let
  version = "1.0.0";

  src = fetchFromGitHub {
    owner = "Mic92";
    repo = "wrap-buddy";
    rev = "ba5ab56ddc572482c26b2cf08414befc5f66ad40";
    hash = "sha256-NlBlJbQsFKDgUtawzAEGF0iIO/xON2LXGw/axFOU4g8=";
  };

  # Get interpreter info from stdenv attributes (avoids IFD)
  dynamicLinker = stdenv.cc.bintools.dynamicLinker;

  libcLib = "${stdenv.cc.libc}/lib";

  # Cross-compilation support:
  # - CC (from stdenv) builds stubs for TARGET platform (what gets patched)
  # - CXX_FOR_BUILD builds wrap-buddy for BUILD platform (what runs the patcher)
  # For native builds, these are the same compiler.
  cxxForBuild = "${buildPackages.stdenv.cc}/bin/c++";

  # Single derivation builds everything:
  # - loader.bin, stub.bin (and 32-bit variants on x86_64)
  # - wrap-buddy C++ patcher with embedded stubs
  wrapBuddy = stdenv.mkDerivation {
    pname = "wrap-buddy";
    inherit version src;

    # depsBuildBuild: tools that run on BUILD and compile for BUILD
    depsBuildBuild = [
      buildPackages.stdenv.cc # C++ compiler for wrap-buddy
    ];

    nativeBuildInputs = [
      binutils # objcopy (processes target ELF files)
      xxd # for embedding stubs (platform-independent)
    ];

    makeFlags = [
      "CXX_FOR_BUILD=${cxxForBuild}"
      "BINDIR=$(out)/bin"
      "LIBDIR=$(out)/lib/wrap-buddy"
      "INTERP=${dynamicLinker}"
      "LIBC_LIB=${libcLib}"
    ]
    ++ lib.optional stdenv.hostPlatform.isx86_64 "BUILD_32BIT=1";

    nativeInstallCheckInputs = [ strace ];
    doInstallCheck = true;
    installCheckTarget = "check";
    enableParallelBuilding = true;

    meta = {
      description = "Patch ELF binaries with stub loader for NixOS compatibility";
      homepage = "https://github.com/Mic92/wrap-buddy";
      mainProgram = "wrap-buddy";
      license = lib.licenses.mit;
      platforms = [
        "x86_64-linux"
        "i686-linux"
        "aarch64-linux"
      ];
    };
  };

  hook = makeSetupHook {
    name = "wrap-buddy-hook";
    propagatedBuildInputs = [ wrapBuddy ];
    passthru.hideFromDocs = true;
    passthru.skipUpdate = true;
    meta = {
      description = "Setup hook that patches ELF binaries with stub loader";
      license = lib.licenses.mit;
      platforms = lib.platforms.linux;
    };
  } "${src}/nix/wrap-buddy-hook.sh";
in
hook
