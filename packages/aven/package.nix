{
  lib,
  stdenv,
  fetchFromGitHub,
  rustPlatform,
  cacert,
  git,
  sqlite,
  libredirect,
  versionCheckHook,
}:

rustPlatform.buildRustPackage (finalAttrs: {
  pname = "aven";
  version = "0.1.36";

  src = fetchFromGitHub {
    owner = "raine";
    repo = "aven";
    tag = "v${finalAttrs.version}";
    hash = "sha256-dzbWemJGxi4J8OX0XSkaIgGm9nhzISZWNPWa/SWJiJM=";
  };

  cargoHash = "sha256-rsFn9qUH4kJZVxVs93d3JqF0UlQs7jOKXxCy8R5/Cnk=";

  # `launchctl print gui/<uid>/...` fails with exit code 125 for the darwin
  # build user, which has no per-user launchd domain, making every doctor
  # invocation (and thus its tests) error out. Degrade to "unknown" instead.
  patches = [ ./daemon-status-unknown-without-gui-domain.patch ];

  # Some tests infer the project key from the checkout directory name
  # ("aven" -> "AVN"), but Nix unpacks into "source".
  postUnpack = ''
    mv source aven
    export sourceRoot=aven
  '';

  # Only build the CLI crate, not the aven-uniffi mobile bindings.
  cargoBuildFlags = [
    "--package"
    "aven"
  ];

  postInstall = ''
    install -d $out/share/aven
    cp -r skills $out/share/aven/skills
  '';

  # git: tests infer the project from the checkout's git repo (see preCheck).
  # sqlite: attachment tests shell out to `sqlite3`.
  # cacert: rustls-native-certs fails without system CA certs in the sandbox.
  nativeCheckInputs = [
    cacert
    git
    sqlite
  ];

  checkFlags = [
    # Needs a system zoneinfo database, which the sandbox lacks
    # (chrono ignores $TZDIR: https://github.com/chronotope/chrono/issues/1265).
    "--skip=local_calendar_dates_use_offsets_across_daylight_saving_boundaries"
    # `aven backup` races its own WAL connection against a `sqlite3 .backup`
    # subprocess and flakes as "database is locked" on loaded runners.
    "--test-threads=1"
    # New in 0.1.29: these tests spawn absolute system binaries (/usr/bin/tee,
    # /usr/bin/false) and compile a fixture with `rustc` at run time, none of
    # which exist in the sandbox, so every invocation fails to start.
    "--skip=tui::app::tests::custom_commands"
  ];

  # Many tests rely on inferring the project from the surrounding git repo;
  # the sandbox is not a git repo, so create one.
  preCheck = ''
    export HOME=$(mktemp -d)
    export SSL_CERT_FILE=${cacert}/etc/ssl/certs/ca-bundle.crt
    git init -q .
  ''
  # iana-time-zone resolves the local zone from /etc/localtime or
  # /etc/timezone (never $TZ); the Linux sandbox has neither, so redirect
  # /etc/timezone to a file naming UTC.
  + lib.optionalString stdenv.hostPlatform.isLinux ''
    echo UTC > "$TMPDIR/timezone"
    export NIX_REDIRECTS=/etc/timezone=$TMPDIR/timezone
    export LD_PRELOAD=${libredirect}/lib/libredirect.so
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [ versionCheckHook ];

  passthru.category = "Workflow & Project Management";

  meta = {
    description = "Local-first task manager for power users and agents";
    homepage = "https://github.com/raine/aven";
    changelog = "https://github.com/raine/aven/blob/v${finalAttrs.version}/CHANGELOG.md";
    license = lib.licenses.mit;
    mainProgram = "aven";
    maintainers = with lib.maintainers; [ sei40kr ];
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
    platforms = lib.platforms.unix;
  };
})
