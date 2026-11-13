{
  lib,
  stdenv,
  flake,
  buildGo127Module,
  buildNpmPackage,
  cacert,
  fetchFromGitHub,
  fetchNpmDeps,
  fetchurl,
  prefetch-npm-deps,
  versionCheckHook,
  makeBinaryWrapper,
  jq,
  unpinGoModVersionHook,
  sqlite,
  callPackage,
  symlinkJoin,
  withCjk ? false,
}:

let
  versionData = builtins.fromJSON (builtins.readFile ./hashes.json);
  inherit (versionData)
    version
    hash
    npmDepsHash
    vendorHash
    litellmSnapshot
    ;

  src = fetchFromGitHub {
    owner = "kenn-io";
    repo = "agentsview";
    tag = "v${version}";
    inherit hash;
  };

  # The //go:embed pricing snapshot is not in the source tree; upstream
  # restores it from a pinned artifact commit over the network. Fetch that blob
  # directly. update.py keeps url/hash in sync from the tagged source.
  litellmSnapshotFile = fetchurl {
    inherit (litellmSnapshot) url hash;
  };

  # @kenn-io/kit-ui is a git dependency whose repo contains symlinks. When
  # prefetch-npm-deps repacks it, the recorded symlink mode differs between
  # Linux (777) and darwin (755), so the FOD hash diverges per platform.
  # Normalize member modes while repacking to keep npmDepsHash identical.
  prefetch-npm-deps' = prefetch-npm-deps.overrideAttrs (old: {
    postPatch = (old.postPatch or "") + ''
      substituteInPlace src/parse/mod.rs \
        --replace-fail '"--sort=name",' '"--sort=name", "--mode=go-w",'
    '';
  });

  frontend = buildNpmPackage {
    pname = "agentsview-frontend";
    inherit version src;
    sourceRoot = "${src.name}/frontend";
    npmDeps = fetchNpmDeps {
      inherit src;
      sourceRoot = "${src.name}/frontend";
      name = "agentsview-frontend-${version}-npm-deps";
      hash = npmDepsHash;
      forceGitDeps = true;
      nativeBuildInputs = [ prefetch-npm-deps' ];
    };
    # @kenn-io/kit-ui is a git dependency with install scripts but no lockfile.
    forceGitDeps = true;
    makeCacheWritable = true;
    # vite-plus eagerly constructs a reqwest client on startup and panics
    # when SSL_CERT_FILE points at stdenv's /no-cert-file.crt sentinel.
    # Give it a real CA bundle so the client builds; the sandbox still
    # blocks any actual network egress.
    env.SSL_CERT_FILE = "${cacert}/etc/ssl/certs/ca-bundle.crt";
    installPhase = ''
      runHook preInstall
      cp -r dist $out
      runHook postInstall
    '';
  };

  # Built from hashes.json pins alone, so an agentsview bump that keeps the pins
  # reuses the sidecar. The wrapper checks the pins against this release.
  cjk = callPackage ./cjk.nix { pins = versionData.cjk; };

  unwrapped = buildGo127Module {
    pname = "agentsview";
    inherit version src vendorHash;

    nativeBuildInputs = [
      jq
      unpinGoModVersionHook
    ];

    # sqlite-vec-go-bindings/cgo needs <sqlite3.h> at build time.
    buildInputs = [ sqlite ];

    subPackages = [ "cmd/agentsview" ];
    tags = [ "fts5" ];
    env.CGO_ENABLED = "1";

    preBuild = ''
      rm -rf internal/web/dist
      cp -r ${frontend} internal/web/dist

      install -Dm644 ${litellmSnapshotFile} internal/pricing/snapshot/litellm_snapshot.json.gz
    '';

    ldflags = [
      "-s"
      "-w"
      "-X main.version=${version}"
      "-X main.commit=v${version}"
      "-X main.buildDate=1970-01-01T00:00:00Z"
    ];

    doCheck = false;

    doInstallCheck = true;
    nativeInstallCheckInputs = [ versionCheckHook ];

    postInstall = lib.optionalString (stdenv.buildPlatform.canExecute stdenv.hostPlatform) ''
      # The source tree has the skill only as a Go template. `agentsview skills
      # install` renders it per harness and adds a header recording a hash of
      # the body, which `agentsview skills list` compares against a fresh render
      # to detect a stale or edited file. A copy taken from the source tree
      # would have neither the harness-specific text nor that header, so only
      # the binary can produce a usable file. The installer writes under $HOME
      # and accepts no other destination, hence the staging home.
      #
      # `skills list --json` reports one row per installed file, so a harness or
      # an artifact added upstream needs no change here. The human table gained
      # a column in 0.45.0 and broke a column-based parse. Each file keeps its
      # path below <home>/.<harness>/<kind>/.
      (
        export HOME="$NIX_BUILD_TOP/agentsview-skills-home"

        "$out/bin/agentsview" skills install

        "$out/bin/agentsview" skills list --json \
          | jq -r '.[]? | "\(.harness) \(.path)"' \
          | while read -r harness path; do
              rel=''${path#"$HOME"/}
              rel=''${rel#*/}
              rel=''${rel#*/}
              install -Dm644 "$path" "$out/share/agentsview/skills/$harness/$rel"
            done

        if [ ! -d "$out/share/agentsview/skills" ]; then
          echo "agentsview: no skills were installed; has 'skills list' changed?" >&2
          exit 1
        fi
      )
    '';

    passthru.category = "Usage Analytics";

    meta = with lib; {
      description = "Local-first viewer and analytics for AI coding agent sessions";
      homepage = "https://github.com/kenn-io/agentsview";
      changelog = "https://github.com/kenn-io/agentsview/releases/tag/v${version}";
      license = licenses.mit;
      sourceProvenance = with sourceTypes; [ fromSource ];
      maintainers = with flake.lib.maintainers; [ ak2k ];
      mainProgram = "agentsview";
      platforms = platforms.unix;
    };
  };

  wrapperArgs = [
    "--set"
    "AGENTSVIEW_TELEMETRY_ENABLED"
    "0"
  ]
  # Set the sidecar path in the wrapper to avoid rebuilding Go/frontend for CJK.
  ++ lib.optionals withCjk [
    "--set"
    "AGENTSVIEW_SIMPLE_DIR"
    "${cjk}/lib/agentsview/simple"
  ];
in
symlinkJoin {
  pname = "agentsview";
  inherit version;
  paths = [ unwrapped ];
  nativeBuildInputs = [ makeBinaryWrapper ];
  postBuild =
    lib.optionalString withCjk ''
      # Reject stale pins and unsupported assignments without executing upstream code.
      check_pin() {
        local found
        found=$(grep -E "^[[:space:]]*((export|readonly|local|declare)[[:space:]]+([^=]*[[:space:]])?)?$1=" \
          ${src}/scripts/build-simple-fts.sh || true)
        if [ "$found" != "$1=\"$2\"" ]; then
          echo "agentsview ${version} scripts/build-simple-fts.sh: expected exactly $1=\"$2\", found: ''${found:-nothing}" >&2
          echo "Remove only the cjk entry from hashes.json, then run packages/agentsview/update.py" >&2
          exit 1
        fi
      }
      check_pin simple_repo ${cjk.simpleGitUrl}
      check_pin simple_commit ${cjk.pins.simple.rev}
      check_pin cppjieba_commit ${cjk.pins.cppjieba.rev}
    ''
    + ''
      wrapProgram $out/bin/agentsview ${lib.escapeShellArgs wrapperArgs}
    '';
  passthru = {
    inherit
      frontend
      unwrapped
      cjk
      withCjk
      ;
    category = "Usage Analytics";
  };
  inherit (unwrapped) meta;
}
