# The registry: the ONE file that knows the layout. name -> path for every
# corepkgs module. scope.nix imports each with the shared module tree, so no
# other file path-imports a sibling - a module names its deps with
# `inherit (scope) ...` instead. Move a file: edit one line here, nothing else.
#
# Every module is a function of `scope` (the memoized tree). Leaves that need
# nothing from it take `_scope:` and ignore it.
{
  # fetch primitives
  fetchurl = ./fetch/fetchurl.nix;
  interpolate = ./fetch/interpolate.nix;
  fetchurlTemplate = ./fetch/fetchurl-template.nix;
  platformSource = ./fetch/platform-source.nix;

  # seed: static busybox+nushell + per-arch platform data
  systems = ./seed/systems.nix;
  seed = ./seed;

  # derivation builders
  mkDrvSh = ./mk/drv-sh.nix;
  mkDrvNu = ./mk/drv-nu.nix;

  # constructors
  mkPackage = ./mk/package.nix;
  checkFhs = ./mk/check-fhs.nix;
  mkCargo = ./mk/cargo;
  mkGo = ./mk/go;
  mkNpm = ./mk/npm;
  mkBun = ./mk/bun;
  mkPnpm = ./mk/pnpm;
  mkPython = ./mk/python;

  # dependency vendorers
  cargoVendor = ./vendor/cargo;
  goVendor = ./vendor/go;
  npmVendor = ./vendor/npm;
  bunVendor = ./vendor/bun;
  pnpmVendor = ./vendor/pnpm;
  pythonVendor = ./vendor/python;

  # toolchain provider + the prebuilt -bin toolchain packages it maps
  toolchains = ./toolchains;
  nodeBin = ./packages/node-bin/package.nix;
  zigBin = ./packages/zig-bin/package.nix;
  bunBin = ./packages/bun-bin/package.nix;
  pnpmBin = ./packages/pnpm-bin/package.nix;
  rustBin = ./packages/rust-bin/package.nix;
  goBin = ./packages/go-bin/package.nix;
  pythonBin = ./packages/python-bin/package.nix;

  # meta helpers - un-called functions taking the CONSUMER's nixpkgs deps
  # (lib / inputs / writeShellApplication), not scope deps; ride as leaves.
  mkUpdater = ./lib/mk-updater.nix;
  mkUpdateScript = ./lib/mk-update-script.nix;
  flakeLib = ./lib/maintainers.nix;
}
