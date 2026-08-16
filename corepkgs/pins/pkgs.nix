# Pin provider sourcing the same tools from the flake's `pkgs`. Pure (touches
# nixpkgs), so CI can rebuild pins from source on a cache miss - the fallback for
# pins/closure.nix. formatelf is rebuilt from the pinned rev.
pkgs:
let
  # single-sourced with packages/formatelf (the auto-patchelf hook builds the same)
  formatelfData = builtins.fromJSON (builtins.readFile ../packages/formatelf/hashes.json);
  formatelf = pkgs.rustPlatform.buildRustPackage {
    pname = "formatelf";
    inherit (formatelfData) version cargoHash;
    src = pkgs.fetchFromGitHub {
      owner = "Mic92";
      repo = "formatelf";
      inherit (formatelfData) rev hash;
    };
    doCheck = false;
  };
in
{
  inherit formatelf;
  glibc = pkgs.glibc;
  gccLib = pkgs.stdenv.cc.cc.lib;
  zlib = pkgs.zlib;
  zstd = pkgs.zstd;
  ripgrep = pkgs.ripgrep;
  coreutils = pkgs.coreutils;
  # manylinux external libs for python wheels
  libffi = pkgs.libffi;
  expat = pkgs.expat;
  ncurses = pkgs.ncurses;
  openssl = pkgs.openssl.out;
  opensslDev = pkgs.openssl.dev;
  sqlite = pkgs.sqlite.out;
  sqliteDev = pkgs.sqlite.dev;
  pkgConfig = pkgs.pkg-config;
  icu = pkgs.icu.out;
  icuDev = pkgs.icu.dev;
  bzip2 = pkgs.bzip2.out;
  xz = pkgs.xz.out;
  bubblewrap = pkgs.bubblewrap;
  socat = pkgs.socat;
}
