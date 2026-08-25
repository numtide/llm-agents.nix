{
  flake,
  stdenv,
  fetchurl,
}:

let
  sourceData = builtins.fromJSON (builtins.readFile ./hashes.json);
  platform = stdenv.hostPlatform.system;
  runtimeMetadata =
    sourceData.runtimeSources.${platform}
      or (throw "Unsupported ChatGPT primary runtime platform: ${platform}");
in
(fetchurl {
  name = baseNameOf runtimeMetadata.url;
  inherit (runtimeMetadata) url hash;
}).overrideAttrs
  {
    # The archive contains non-redistributable modules. It is reachable only from
    # the explicit opt-in runtime graph and is always fetched locally.
    allowSubstitutes = false;
    preferLocalBuild = true;

    passthru = {
      inherit runtimeMetadata;
    };

    meta = {
      homepage = "https://chatgpt.com";
      license = flake.lib.licenses.unfree;
      sourceProvenance = with flake.lib.sourceTypes; [ binaryNativeCode ];
      platforms = builtins.attrNames sourceData.runtimeSources;
    };
  }
