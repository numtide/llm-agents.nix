{
  lib,
  flake,
  rustPlatform,
  fetchFromGitHub,
  pkg-config,
  aws-lc,
  versionCheckHook,
}:

let
  data = builtins.fromJSON (builtins.readFile ./hashes.json);

  # Upstream's tagged Cargo.lock is generated with the dev-local
  # `[patch.crates-io]` config active, so the fsqlite-* entries have no
  # `source =` field and are not vendored.  Reproduce that environment by
  # placing a sibling frankensqlite checkout and installing the upstream
  # patch table (scripts/dev-local-frankensqlite.toml) as .cargo/config.toml.
  # https://github.com/Dicklesworthstone/beads_rust/issues/183
  frankensqlite = fetchFromGitHub {
    owner = "Dicklesworthstone";
    repo = "frankensqlite";
    inherit (data.frankensqlite) rev hash;
  };
in
rustPlatform.buildRustPackage {
  pname = "beads-rust";
  inherit (data) version cargoHash;

  src = fetchFromGitHub {
    owner = "Dicklesworthstone";
    repo = "beads_rust";
    tag = "v${data.version}";
    inherit (data) hash;
  };

  nativeBuildInputs = [ pkg-config ];

  buildInputs = [ aws-lc ];

  postUnpack = ''
    cp -r ${frankensqlite} frankensqlite
    chmod -R u+w frankensqlite
  '';

  postPatch = ''
    mkdir -p .cargo
    cp scripts/dev-local-frankensqlite.toml .cargo/config.toml
  '';

  env = {
    # fsqlite uses #![feature(peer_credentials_unix_socket)] which requires nightly.
    # RUSTC_BOOTSTRAP=1 enables nightly features on stable rustc.
    RUSTC_BOOTSTRAP = 1;
    AWS_LC_SYS_USE_SYSTEM = "1";
  };

  # Disable self_update feature — doesn't make sense in Nix
  buildNoDefaultFeatures = true;

  # Tests require a git repository context
  doCheck = false;

  doInstallCheck = true;
  nativeInstallCheckInputs = [ versionCheckHook ];

  passthru.category = "Workflow & Project Management";

  meta = with lib; {
    description = "Fast Rust port of beads - a local-first issue tracker for git repositories";
    homepage = "https://github.com/Dicklesworthstone/beads_rust";
    changelog = "https://github.com/Dicklesworthstone/beads_rust/releases/tag/v${data.version}";
    downloadPage = "https://github.com/Dicklesworthstone/beads_rust/releases";
    license = licenses.mit;
    sourceProvenance = with sourceTypes; [ fromSource ];
    maintainers = with flake.lib.maintainers; [ afterthought ];
    mainProgram = "br";
    platforms = platforms.unix;
  };
}
