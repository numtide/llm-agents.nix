# formatelf: ELF interpreter/RPATH patcher + an autoPatchelfHook-equivalent
# setup hook (auto-formatelf) backed by it.
{
  lib,
  stdenv,
  rustPlatform,
  fetchFromGitHub,
  makeSetupHook,
}:

let
  # version + rev + src/cargo hashes live in ./hashes.json (single-sourced with
  # pins/pkgs.nix, which rebuilds the same formatelf for the pin fallback).
  data = builtins.fromJSON (builtins.readFile ./hashes.json);

  # Rust source + setup-hook script fetched from upstream; Nix packaging is
  # vendored in-tree.
  src = fetchFromGitHub {
    owner = "Mic92";
    repo = "formatelf";
    inherit (data) rev hash;
  };

  formatelf = rustPlatform.buildRustPackage {
    pname = "formatelf";
    inherit (data) version;
    inherit src;

    inherit (data) cargoHash;

    # test suite needs zig-built fixtures + a reference patchelf, absent from the
    # sandbox.
    doCheck = false;

    # auto-formatelf: multi-call personality selected by argv[0].
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

  # bintools supplies $NIX_BINTOOLS, from which auto-formatelf reads the dynamic
  # linker and libc.
  hook = makeSetupHook {
    name = "auto-formatelf-hook";
    propagatedBuildInputs = [
      formatelf
      stdenv.cc.bintools
    ];
    passthru.hideFromDocs = true;
    meta = {
      description = "Setup hook that patches ELF binaries via formatelf";
      license = lib.licenses.mit;
      platforms = lib.platforms.linux;
    };
  } "${src}/auto-formatelf-hook.sh";
in
hook
