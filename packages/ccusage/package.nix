{
  lib,
  fetchFromGitHub,
  fetchurl,
  rustPlatform,
  pkg-config,
  stdenv,
  aws-lc,
  zstd,
  versionCheckHook,
  versionCheckHomeHook,
}:

let
  # build.rs embeds a LiteLLM pricing snapshot. Without a local file it
  # downloads model_prices_and_context_window.json at build time, which the
  # sandbox forbids, so pass a pinned copy via CCUSAGE_PRICING_JSON_PATH.
  # build.rs resolves that URL from nodes.litellm.locked in the tagged tree's
  # flake.lock, so the pin must match it exactly or we embed different prices
  # than upstream ships. update.py re-reads it from the tag on every bump.
  litellmRev = "f96200bcea3a08adcd08ad4eb5ad169d226cdda5";
  litellm-pricing = fetchurl {
    url = "https://raw.githubusercontent.com/BerriAI/litellm/${litellmRev}/model_prices_and_context_window.json";
    hash = "sha256-yNDB8oJhPmh0ZUuJ2JBMg8sqAno/ejCeqWtdMdCLkus=";
  };
in
rustPlatform.buildRustPackage rec {
  pname = "ccusage";
  version = "20.0.45";

  src = fetchFromGitHub {
    owner = "ccusage";
    repo = "ccusage";
    tag = "v${version}";
    hash = "sha256-4nFUpdXNtWOLJuYfxjb0hkT/y1Q3x6HUy7b8bxMmdYg=";
  };

  sourceRoot = "${src.name}/rust";

  cargoHash = "sha256-YcNmxK/+aOI7G0tK4VN1suc7oG4Q9AsT0eBLjk4zUgE=";

  cargoBuildFlags = [
    "-p"
    "ccusage"
    "--bin"
    "ccusage"
  ];

  # Workspace tests need fixture crates and insta snapshots that the tagged
  # tarball builds cannot satisfy; upstream's own derivation skips them too.
  doCheck = false;

  nativeBuildInputs = [ pkg-config ];

  buildInputs = [
    aws-lc
    zstd
  ];

  env = {
    # nixpkgs' Darwin cc-wrapper injects -liconv even though ccusage references no
    # iconv symbols, leaving an unused store dependency (upstream ccusage#1251).
    # dead_strip_dylibs drops load commands whose symbols are never referenced.
    RUSTFLAGS = lib.optionalString stdenv.hostPlatform.isDarwin "-C link-arg=-Wl,-dead_strip_dylibs";

    CCUSAGE_PRICING_JSON_PATH = litellm-pricing;

    # build.rs falls back to the tagged tree's own version, but the tag is
    # authoritative for what we claim to ship.
    CCUSAGE_VERSION = version;

    AWS_LC_SYS_USE_SYSTEM = "1";
    ZSTD_SYS_USE_PKG_CONFIG = "1";
  };

  doInstallCheck = true;

  nativeInstallCheckInputs = [
    versionCheckHook
    versionCheckHomeHook
  ];

  passthru.category = "Usage Analytics";

  meta = with lib; {
    description = "Analyze coding agent CLI token usage and costs from local data";
    homepage = "https://ccusage.com/";
    changelog = "https://github.com/ccusage/ccusage/releases/tag/v${version}";
    license = licenses.mit;
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
    maintainers = with maintainers; [ ryoppippi ];
    mainProgram = "ccusage";
    platforms = platforms.unix;
  };
}
