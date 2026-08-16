# Fetch the prebuilt librusty_v8 static lib (+ optional src_binding) for the host.
{
  lib,
  stdenv,
  fetchurl,
}:

lib.makeOverridable (
  {
    version,
    hashes,
    # "release", or a feature-suffixed flavor like "ptrcomp_sandbox_release".
    profile ? "release",
    baseUrl ? "https://github.com/denoland/rusty_v8/releases/download/v${version}",
    # rusty_v8 >= 150 needs the matching src_binding_*.rs too; when set,
    # it's exposed as passthru.srcBinding.
    srcBindingHashes ? null,
  }:

  let
    target = stdenv.hostPlatform.rust.rustcTarget;
  in
  fetchurl {
    name = "librusty_v8-${version}";
    url = "${baseUrl}/librusty_v8_${profile}_${target}.a.gz";
    hash = hashes.${stdenv.hostPlatform.system};
    meta.sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    passthru = lib.optionalAttrs (srcBindingHashes != null) {
      srcBinding = fetchurl {
        name = "src_binding-${version}.rs";
        url = "${baseUrl}/src_binding_${profile}_${target}.rs";
        hash = srcBindingHashes.${stdenv.hostPlatform.system};
      };
    };
  }
)
