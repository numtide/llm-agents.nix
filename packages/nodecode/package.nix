{
  lib,
  pkgs,
  flake,
  fetchFromGitHub,
}:

let
  versionData = lib.importJSON ./hashes.json;
  inherit (versionData) version;

  src = fetchFromGitHub {
    owner = "nodecode-ai";
    repo = "nodecode";
    rev = "c6418bc";
    inherit (versionData) hash;
  };

  # Vendored copy of upstream's nix/package.nix, refreshed by update.py.
  upstream = import ./upstream-package.nix {
    inherit src;
    pkgs = pkgs // {
      inherit sbcl;
    };
  };

  # Empty entries are meaningful in ASDF's search paths, but makeBinaryWrapper
  # rejects them for --prefix.
  sbcl = pkgs.sbcl // {
    withPackages =
      f:
      (pkgs.sbcl.withPackages f).overrideAttrs (old: {
        installPhase =
          lib.replaceStrings
            [ "--prefix CL_SOURCE_REGISTRY :" "--prefix ASDF_OUTPUT_TRANSLATIONS :" ]
            [ "--set CL_SOURCE_REGISTRY" "--set ASDF_OUTPUT_TRANSLATIONS" ]
            old.installPhase;
      });
  };

in
upstream.overrideAttrs (old: {
  name = "nodecode-${version}";

  passthru = old.passthru // {
    category = "AI Assistants";
  };

  meta = old.meta // {
    description = "A self-modifying agent organism in SBCL";
    homepage = "https://github.com/nodecode-ai/nodecode";
    changelog = "https://github.com/nodecode-ai/nodecode/releases/tag/v${version}";
    license = lib.licenses.mit;
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
    maintainers = with flake.lib.maintainers; [ luciusmagn ];
  };
})