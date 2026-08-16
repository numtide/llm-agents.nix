# fetchurl on the builtin:fetchurl builder: a leaf derivation, no nixpkgs
# wrapper or stdenv graph. Same output path as pkgs.fetchurl for url + hash.
# Args closed on purpose - no unpack/auth/curl opts, so extras fail loudly.
# executable => recursive NAR hash + +x bit, for runnable binaries.
_scope:
{
  url,
  hash,
  executable ? false,
  name ? baseNameOf url, # override when the URL basename isn't a legal store name
}:
derivation {
  inherit url executable name;
  builder = "builtin:fetchurl";
  system = "builtin";
  urls = [ url ];
  outputHash = hash;
  outputHashMode = if executable then "recursive" else "flat";
  outputHashAlgo = null;
  preferLocalBuild = true;
  unpack = false;
}
