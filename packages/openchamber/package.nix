{
  lib,
  flake,
  buildNpmPackage,
  fetchurl,
  git,
  jq,
  mkUpdater,
  opencode2,
  ripgrep,
  runCommand,
  versionCheckHook,
  versionCheckHomeHook,
}:

let
  versionData = lib.importJSON ./hashes.json;
  inherit (versionData) version;

  # The npm tarball ships the built UI (dist/ + server/) but no lockfile, so
  # vendor one next to the source. The lock is generated without
  # devDependencies (build-only React/Vite tooling) and without the scripts
  # block, whose `prepack` runs a monorepo build the tarball does not carry.
  # Mirror both deletions here or `npm ci` re-resolves the whole tree.
  srcWithLock = runCommand "openchamber-src-with-lock" { nativeBuildInputs = [ jq ]; } ''
    mkdir -p $out
    tar -xzf ${
      fetchurl {
        url = "https://registry.npmjs.org/@openchamber/web/-/web-${version}.tgz";
        hash = versionData.sourceHash;
      }
    } -C $out --strip-components=1
    jq 'del(.devDependencies) | del(.scripts)' $out/package.json > $out/package.json.tmp
    mv $out/package.json.tmp $out/package.json
    cp ${./package-lock.json} $out/package-lock.json
  '';
in
buildNpmPackage {
  pname = "openchamber";
  inherit version;

  src = srcWithLock;

  npmDepsHash = versionData.npmDepsHash;
  npmDepsFetcherVersion = 2;

  # Install scripts build native addons from source: node-pty/bun-pty for the
  # in-browser terminal and sherpa-onnx-node for local dictation. Both ship
  # prebuilt platform packages, and the server imports them lazily, so skip
  # the compiles that the Nix sandbox cannot run offline.
  npmInstallFlags = [ "--ignore-scripts" ];
  npmRebuildFlags = [ "--ignore-scripts" ];

  # dist/ is prebuilt in the tarball; the build script needs the monorepo.
  dontNpmBuild = true;

  makeWrapperArgs = [
    # OpenChamber drives an OpenCode 2.x server and refuses a build older than
    # the floor it ships with (2.2.4 as of 2.6.0, no newer than the in-repo
    # OpenCode 2 there). It reads OPENCODE_BINARY before searching PATH for
    # `opencode`, so bind it straight to that build. `--set-default` leaves the
    # variable writable for people running their own checkout.
    "--set-default OPENCODE_BINARY ${lib.getExe opencode2}"
    # The server shells out to git for worktrees and to ripgrep for search.
    "--prefix PATH : ${
      lib.makeBinPath [
        git
        ripgrep
      ]
    }"
  ];

  doInstallCheck = true;
  nativeInstallCheckInputs = [
    versionCheckHook
    versionCheckHomeHook
  ];
  versionCheckProgramArg = "--version";

  passthru.category = "AI Coding Agents";
  passthru.updater = mkUpdater {
    kind = "npm";
    purl = "pkg:npm/%40openchamber/web";
    stripDevDependencies = true;
  };

  meta = {
    description = "Web and desktop UI for the OpenCode AI coding agent";
    longDescription = ''
      OpenChamber turns OpenCode sessions into a browser and desktop
      workspace: project sessions, diffs, terminals, worktrees and mobile
      access over an encrypted relay. This package installs the web server and
      its `openchamber` CLI, wired to the in-repo OpenCode 2 build it requires.
    '';
    homepage = "https://github.com/openchamber/openchamber";
    changelog = "https://github.com/openchamber/openchamber/releases/tag/v${version}";
    downloadPage = "https://www.npmjs.com/package/@openchamber/web?activeTab=versions";
    license = lib.licenses.mit;
    sourceProvenance = with lib.sourceTypes; [ binaryBytecode ];
    maintainers = with flake.lib.maintainers; [ dxops ];
    mainProgram = "openchamber";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
      "aarch64-darwin"
    ];
  };
}
