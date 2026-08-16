# cc-switch-cli - built from source on corepkgs (nixpkgs-free) via mkCargo. The
# crate lives in the `src-tauri` subdir but is a plain CLI (no tauri frontend);
# it installs the `cc-switch` binary. Several deps bundle their own C and compile
# it through the `cc` crate (rusqlite "bundled", rquickjs' quickjs, ring via
# rustls, brotli), which uses our `zig cc` wrapper - no external C libs.
{
  mkCargo,
  coreFetchurl,
  flake,
}:
let
  data = builtins.fromJSON (builtins.readFile ./hashes.json);
in
mkCargo {
  pname = "cc-switch-cli";
  inherit (data) version;
  src = coreFetchurl {
    url = "https://github.com/SaladDay/cc-switch-cli/archive/refs/tags/v${data.version}.tar.gz";
    inherit (data) hash;
  };
  cargoLock = ./Cargo.lock;
  sourceRoot = "src-tauri";
  binaries = [ "cc-switch" ];
  # Manifest gates on rustc 1.91.1; our pinned toolchain is 1.90.0. The code
  # itself compiles on 1.90, so skip the rust-version check.
  cargoBuildFlags = [ "--ignore-rust-version" ];

  category = "Claude Code Ecosystem";
  meta = {
    description = "CLI version of CC Switch - All-in-One Assistant for Claude Code, Codex & Gemini CLI";
    homepage = "https://github.com/SaladDay/cc-switch-cli";
    changelog = "https://github.com/SaladDay/cc-switch-cli/releases/tag/v${data.version}";
    downloadPage = "https://github.com/SaladDay/cc-switch-cli/releases";
    license = flake.lib.licenses.mit;
    sourceProvenance = [ flake.lib.sourceTypes.fromSource ];
    maintainers = [ flake.lib.maintainers.zrubing ];
    mainProgram = "cc-switch";
  };
}
