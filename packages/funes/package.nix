{
  lib,
  rustPlatform,
  fetchFromGitHub,
  protobuf,
  versionCheckHook,
  versionCheckHomeHook,
}:

rustPlatform.buildRustPackage (finalAttrs: {
  pname = "funes";
  version = "1.11.0";

  src = fetchFromGitHub {
    owner = "huggingface";
    repo = "funes";
    tag = "v${finalAttrs.version}";
    hash = "sha256-7y1EITcVHOEry0J5V/ahc3bBbAk1EacW95Bi4lSmBd4=";
  };

  cargoHash = "sha256-0HWamJ1c31hs0ErpUUGENrx+l3IGegKZRg+4evS07oA=";

  postPatch = ''
    # Release CI stamps the version on the tag; the tagged Cargo.toml still
    # carries the dev label, which `funes --version` then reports.
    sed -i -E 's/^version = "[^"]*"$/version = "${finalAttrs.version}"/' Cargo.toml

    # nixpkgs' rustc links an LLVM whose vpdpbusd.512 / vpdpwssd.512
    # signatures disagree with stdarch, so route lance's VNNI calls through
    # exact AVX-512BW equivalents. The vendored crates live outside the source.
    for crate in $(grep -rlE '_mm512_dp(busd|wssd)_epi32' "$NIX_BUILD_TOP/$(stripHash "$cargoDeps")/source-registry-0" \
        | sed -E 's|(/source-registry-0/[^/]+)/.*|\1|' | sort -u); do
      grep -rlE '_mm512_dp(busd|wssd)_epi32' "$crate" \
        | xargs sed -i -E 's/_mm512_dp(busd|wssd)_epi32\(/crate::nix_vnni_shim::dp\1(/g'
      cat ${./vnni-shim.rs} >> "$crate/src/lib.rs"
    done
  '';

  # lance's protobuf schemas are generated at build time
  nativeBuildInputs = [ protobuf ];

  # lance's suite is slow and wants network fixtures
  doCheck = false;

  doInstallCheck = true;
  nativeInstallCheckInputs = [
    versionCheckHook
    versionCheckHomeHook
  ];

  passthru.category = "Memory & Code Intelligence";

  meta = with lib; {
    description = "Searchable memory of past AI agent sessions, exposed over MCP";
    homepage = "https://github.com/huggingface/funes";
    changelog = "https://github.com/huggingface/funes/releases/tag/v${finalAttrs.version}";
    license = licenses.asl20;
    sourceProvenance = with sourceTypes; [ fromSource ];
    maintainers = with maintainers; [ happysalada ];
    mainProgram = "funes";
    platforms = platforms.unix;
  };
})
