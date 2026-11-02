{
  lib,
  fetchFromGitHub,
  fetchPnpmDeps,
  fetchurl,
  chromium,
  makeBinaryWrapper,
  nodejs-slim_22,
  pnpmConfigHook,
  pnpm_11,
  rustPlatform,
  stdenv,
}:

let
  pname = "agent-browser";
  version = "0.41.1";

  # Node 24's worker_threads teardown double-closes file descriptors
  # (Environment::RunCleanup closing an fd number that the OS has already
  # recycled into a guarded fd), which the Darwin kernel punishes with
  # EXC_GUARD/SIGKILL, so pnpm dies with "Killed: 9" right after the
  # download phase. Run pnpm on Node 22 LTS, which does not exhibit this.
  pnpm = pnpm_11.override { nodejs-slim = nodejs-slim_22; };

  # Vendored Geist variable font (OFL-1.1) pinned to a specific upstream
  # commit so the dashboard's next/font/local build is fully offline.
  geistVariable = fetchurl {
    url = "https://raw.githubusercontent.com/vercel/geist-font/77f0563c03009d6c15c6342183fa53b352255b22/packages/next/dist/fonts/geist-sans/Geist-Variable.woff2";
    hash = "sha256-L/6+mT6WkGmpeJ0VFkt3FdQkkbWDVRbF47k11fgbBfE=";
  };

  src = fetchFromGitHub {
    owner = "vercel-labs";
    repo = "agent-browser";
    # Upstream has a branch and a tag both named v<version>, so the plain
    # archive URL is ambiguous ("multiple possibilities"). Pin the tag ref.
    tag = "v${version}";
    hash = "sha256-/YPVYdRNhOkW09WF63xhSwELNzv/D1cOvQep5taIlVQ=";
  };

  dashboard = stdenv.mkDerivation {
    pname = "${pname}-dashboard";
    inherit version src;

    nativeBuildInputs = [
      nodejs-slim_22
      pnpm
      pnpmConfigHook
    ];

    # Restrict the install to the dashboard workspace; the full workspace
    # install pulls in ~1200 packages the dashboard build never uses.
    pnpmWorkspaces = [ "dashboard" ];

    pnpmDeps = fetchPnpmDeps {
      pname = "${pname}-dashboard";
      inherit version src pnpm;
      pnpmWorkspaces = [ "dashboard" ];
      hash = "sha256-9PXr76pm/3QR25tSxP0uqV462UGraSbhCRigpg2kbww=";
      fetcherVersion = 4;
    };

    # next/font/google fetches Geist from fonts.googleapis.com at build
    # time, which the Nix sandbox blocks. Vendor the upstream Geist
    # variable woff2 and rewrite layout.tsx to use next/font/local.
    postPatch = ''
      install -Dm644 ${geistVariable} packages/dashboard/src/app/Geist-Variable.woff2
      substituteInPlace packages/dashboard/src/app/layout.tsx \
        --replace-fail 'import { Geist } from "next/font/google"' 'import Geist from "next/font/local"' \
        --replace-fail 'Geist({ subsets: ["latin"], variable: "--font-sans" })' 'Geist({ src: "./Geist-Variable.woff2", variable: "--font-sans", display: "swap" })'
    '';

    buildPhase = ''
      runHook preBuild
      cd packages/dashboard
      pnpm build
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p $out
      cp -r out/. $out/
      runHook postInstall
    '';
  };
in
rustPlatform.buildRustPackage {
  inherit pname version src;

  sourceRoot = "source/cli";

  cargoHash = "sha256-LSBCYZtGjWmQRE7AXRpxEwyDZySEkRsPdTZbH8JIdzc=";

  nativeBuildInputs = lib.optional stdenv.hostPlatform.isLinux makeBinaryWrapper;
  buildInputs = lib.optional stdenv.hostPlatform.isLinux chromium;

  # Upstream enables fat LTO with codegen-units=1 while pulling in the full
  # `image` crate (avif/webp/tiff/jpeg/png/gif codecs). The final monolithic
  # LTO link OOMs rustc on the aarch64-linux builder. Thin LTO keeps most of
  # the optimisation at a fraction of the peak memory.
  env.CARGO_PROFILE_RELEASE_LTO = "thin";

  # cargo-auditable panics on aarch64-darwin with this crate's dependency tree
  auditable = !stdenv.hostPlatform.isDarwin;

  # Auth/credential tests require a keyring unavailable in the sandbox
  doCheck = false;

  postPatch = ''
    # Skill discovery walks up from the executable looking for a directory
    # that contains skills/. Point it at $out/share/agent-browser instead so
    # both skills/ and skill-data/ are found without polluting $out.
    substituteInPlace src/skills.rs \
      --replace-fail \
        'fn find_package_root() -> Option<PathBuf> {' \
        'fn find_package_root() -> Option<PathBuf> {
    let nix_root = PathBuf::from("${placeholder "out"}/share/agent-browser");
    if nix_root.join("skills").is_dir() {
        return Some(nix_root);
    }'

    substituteInPlace build.rs \
      --replace-fail 'Path::new("../packages/dashboard/out")' 'Path::new("${dashboard}")'
    substituteInPlace src/native/stream/http.rs \
      --replace-fail '#[folder = "../packages/dashboard/out/"]' '#[folder = "${dashboard}/"]'
  '';

  postInstall = ''
    mkdir -p $out/share/agent-browser
    cp -r ../skills ../skill-data $out/share/agent-browser/
  ''
  + lib.optionalString stdenv.hostPlatform.isLinux ''
    wrapProgram $out/bin/agent-browser \
      --set AGENT_BROWSER_EXECUTABLE_PATH ${chromium}/bin/chromium
  '';

  passthru = {
    inherit dashboard;
    category = "Utilities";
  };

  meta = {
    description = "Headless browser automation CLI for AI agents";
    homepage = "https://github.com/vercel-labs/agent-browser";
    changelog = "https://github.com/vercel-labs/agent-browser/releases/tag/v${version}";
    license = lib.licenses.asl20;
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
    platforms = lib.platforms.all;
    mainProgram = "agent-browser";
  };
}
