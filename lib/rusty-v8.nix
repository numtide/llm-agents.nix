{
  lib,
  stdenv,
  fetchurl,
}:

lib.makeOverridable (
  {
    version,
    hashes,
  }:

  fetchurl {
    name = "librusty_v8-${version}";
    url = "https://github.com/denoland/rusty_v8/releases/download/v${version}/librusty_v8_release_${stdenv.hostPlatform.rust.rustcTarget}.a.gz";
    hash = hashes.${stdenv.hostPlatform.system};
    meta.sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  }
)
