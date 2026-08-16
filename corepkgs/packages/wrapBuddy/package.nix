# wrapBuddy: patches ELF binaries with a stub loader for NixOS, plus the setup
# hook that applies it.
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
  # version + rev + src hash live in ./hashes.json
  data = builtins.fromJSON (builtins.readFile ./hashes.json);

  src = fetchFromGitHub {
    owner = "Mic92";
    repo = "wrap-buddy";
    inherit (data) rev hash;
  };

  # from stdenv attrs to avoid IFD
  dynamicLinker = stdenv.cc.bintools.dynamicLinker;

  libcLib = "${stdenv.cc.libc}/lib";

  # cross: CC (stdenv) builds stubs for TARGET (patched); CXX_FOR_BUILD builds the
  # wrap-buddy patcher for BUILD (runs it). Same compiler on native builds.
  cxxForBuild = "${buildPackages.stdenv.cc}/bin/c++";

  # one derivation builds loader.bin, stub.bin (+ 32-bit variants on x86_64) and
  # the wrap-buddy C++ patcher with embedded stubs.
  wrapBuddy = stdenv.mkDerivation {
    pname = "wrap-buddy";
    inherit src;
    inherit (data) version;

    # runs on BUILD, compiles for BUILD
    depsBuildBuild = [
      buildPackages.stdenv.cc # C++ compiler for wrap-buddy
    ];

    nativeBuildInputs = [
      binutils # objcopy: processes target ELFs
      xxd # embeds stubs
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
    meta = {
      description = "Setup hook that patches ELF binaries with stub loader";
      license = lib.licenses.mit;
      platforms = lib.platforms.linux;
    };
  } "${src}/nix/wrap-buddy-hook.sh";
in
hook
