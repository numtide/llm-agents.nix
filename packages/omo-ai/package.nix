{
  lib,
  flake,
  buildNpmPackage,
  fetchurl,
  fd,
  mkUpdater,
  nodejs,
  python3,
  ripgrep,
  runCommand,
  stdenv,
  versionCheckHook,
  versionCheckHomeHook,
  wrapBuddy,
  writeShellScriptBin,
}:

let
  versionData = lib.importJSON ./hashes.json;

  # The npm tarball ships no lockfile; package-lock.json and hashes.json are
  # regenerated together by the npm updater flow.
  #
  # omo-ai's pinned engine @code-yeongyu/senpi bundles a complete node_modules
  # inside its tarball, so the lockfile records its dependencies as `inBundle`
  # entries without registry metadata. `npm install` still resolves some of
  # them from manifests (peer dependencies of the bundled
  # @anthropic-ai/claude-agent-sdk, and the declared-vs-bundled version
  # conflicts for https-proxy-agent/zod), and the offline npm cache only
  # carries packuments for entries with `resolved`. Merge in top-level
  # registry entries for those packages (versions senpi declares) so the
  # prefetcher caches their packuments; npm prunes the packages themselves
  # from the tree again as unneeded.
  srcWithLock =
    runCommand "omo-ai-src-with-lock"
      {
        nativeBuildInputs = [ python3 ];
      }
      ''
        mkdir -p $out
        tar -xzf ${
          fetchurl {
            url = "https://registry.npmjs.org/omo-ai/-/omo-ai-${versionData.version}.tgz";
            hash = versionData.sourceHash;
          }
        } -C $out --strip-components=1
        install -m 644 ${./package-lock.json} $out/package-lock.json
        python3 - "$out/package-lock.json" ${./packument-entries.json} <<'PY'
        import json
        import sys

        lock_path, entries_path = sys.argv[1], sys.argv[2]
        with open(lock_path) as f:
            lock = json.load(f)
        with open(entries_path) as f:
            entries = json.load(f)["packages"]
        for key, entry in entries.items():
            lock["packages"].setdefault(key, entry)
        with open(lock_path, "w") as f:
            json.dump(lock, f, indent=2)
        PY
      '';

  # The pinned engine @code-yeongyu/senpi declares dependencies that disagree
  # with the node_modules bundled inside its tarball (https-proxy-agent 9.1.0
  # vs 7.0.6, zod 4.4.3 vs 3.25.76). `npm ci` validates both sides and
  # refuses; upstream's own installer is a plain `npm install`, which keeps
  # the bundled versions. npmConfigHook hardcodes `npm ci`, so shadow `npm`
  # on PATH and translate the verb for this build.
  npmCiShim = writeShellScriptBin "npm" ''
    if [ "''${1:-}" = ci ]; then
      shift
      set -- install "$@"
    fi
    exec '${nodejs}/bin/npm' "$@"
  '';
in
buildNpmPackage {
  npmDepsFetcherVersion = 2;
  pname = "omo-ai";
  version = versionData.version;

  src = srcWithLock;

  npmDepsHash = versionData.npmDepsHash;
  makeCacheWritable = true;
  dontNpmBuild = true;

  # The prebuilt `claude` binary from @anthropic-ai/claude-agent-sdk embeds
  # the bun runtime at the tail of the executable; stripping corrupts it.
  dontStrip = true;

  nativeBuildInputs = [ npmCiShim ] ++ lib.optionals stdenv.hostPlatform.isLinux [ wrapBuddy ];

  makeWrapperArgs = [
    "--prefix PATH : ${
      lib.makeBinPath [
        nodejs
        fd
        ripgrep
      ]
    }"
    # Senpi needs fd/rg at runtime (same as pi); keep telemetry off unless
    # the user opts in (mirrors the pi package's PI_TELEMETRY=0).
    "--set-default OMO_TELEMETRY 0"
    "--set-default OMO_SEND_ANONYMOUS_TELEMETRY 0"
  ];

  postInstall = ''
    # Upstream postinstall (skipped by --ignore-scripts): bump the
    # claudeCodeVersion floor baked into senpi's pi-ai build. No-op when the
    # engine already reports >= the floor.
    OMO_SENPI_PATCH_ROOT="$out/lib/node_modules/omo-ai/node_modules/@code-yeongyu/senpi" \
      "${lib.getExe nodejs}" "$out/lib/node_modules/omo-ai/bin/senpi-patch.mjs"
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [
    versionCheckHook
    versionCheckHomeHook
  ];

  passthru.category = "AI Coding Agents";
  passthru.updater = mkUpdater {
    kind = "npm";
    purl = "pkg:npm/omo-ai?x_dist_tag=beta";
  };

  meta = {
    description = "Standalone Senpi edition of Oh My OpenAgent (the omo coding agent)";
    homepage = "https://github.com/code-yeongyu/oh-my-openagent";
    changelog = "https://github.com/code-yeongyu/oh-my-openagent/releases";
    license = lib.licenses.mit;
    sourceProvenance = with lib.sourceTypes; [
      fromSource
      binaryNativeCode
    ];
    maintainers = with flake.lib.maintainers; [ ankarhem ];
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
      "aarch64-darwin"
    ];
    mainProgram = "omo";
  };
}
