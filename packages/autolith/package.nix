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
    owner = "lambda-symbolics";
    repo = "autolith";
    tag = "v${version}";
    inherit (versionData) hash;
  };

  # Vendored copy of upstream's nix/package.nix, refreshed by update.py.
  upstream = import ./upstream-package.nix {
    inherit src;
    pkgs = pkgs // {
      inherit sbcl;
      # cargoSetupHook forbids the vendored libgit2 that fff-c relies on
      rustPlatform = pkgs.rustPlatform // {
        buildRustPackage =
          args:
          pkgs.rustPlatform.buildRustPackage (
            args // { buildInputs = args.buildInputs or [ ] ++ [ pkgs.libgit2 ]; }
          );
      };
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
  name = "autolith-${version}";

  passthru = old.passthru // {
    category = "AI Assistants";
  };

  meta = old.meta // {
    description = "Live, self-modifying Common Lisp AI agent";
    homepage = "https://github.com/lambda-symbolics/autolith";
    changelog = "https://github.com/lambda-symbolics/autolith/releases/tag/v${version}";
    license = lib.licenses.isc;
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
    maintainers = with flake.lib.maintainers; [ luciusmagn ];
  };
})
