{
  lib,
  stdenv,
  rustPlatform,
  fetchFromGitHub,
  makeSetupHook,
}:

let
  version = "0.2.2";

  # Nix packaging is vendored in-tree; the Rust source and the setup-hook shell
  # script are fetched from upstream as a fixed-output derivation.
  src = fetchFromGitHub {
    owner = "Mic92";
    repo = "formatelf";
    tag = "v${version}";
    hash = "sha256-0Xm+KcrPidtFKF5TkNPVvMp0aYKPkXBStP4vrdVRXQY=";
  };

  formatelf = rustPlatform.buildRustPackage {
    pname = "formatelf";
    inherit version src;

    cargoHash = "sha256-agrxlg96UT5OVK+eBiq+BhRGVU9noi4D/jKPUvGZzNE=";

    # The test suite needs zig-built fixtures and a reference patchelf, neither
    # of which exists in the build sandbox.
    doCheck = false;

    # auto-formatelf is the multi-call personality selected by argv[0].
    postInstall = ''
      ln -s formatelf $out/bin/auto-formatelf
    '';

    meta = {
      description = "Modify the dynamic linker and RPATH of ELF executables";
      homepage = "https://github.com/Mic92/formatelf";
      license = lib.licenses.mit;
      mainProgram = "formatelf";
      platforms = lib.platforms.linux;
    };
  };

  # Drop-in equivalent of nixpkgs' autoPatchelfHook, backed by auto-formatelf.
  # The bintools dependency supplies $NIX_BINTOOLS, from which auto-formatelf
  # reads the dynamic linker and libc.
  hook = makeSetupHook {
    name = "auto-formatelf-hook";
    propagatedBuildInputs = [
      formatelf
      stdenv.cc.bintools
    ];
    passthru.hideFromDocs = true;
    passthru.skipUpdate = true;
    # Standalone binary for patching ELFs outside a build (e.g. at runtime).
    passthru.bin = formatelf;
    meta = {
      description = "Setup hook that patches ELF binaries via formatelf";
      license = lib.licenses.mit;
      platforms = lib.platforms.linux;
    };
  } "${src}/auto-formatelf-hook.sh";
in
hook
