{
  lib,
  stdenv,
  fetchFromGitHub,
  bun2nix,
  bun,
  makeWrapper,
  python3,
  versionCheckHook,
  versionCheckHomeHook,
  plannotatorSem,
}:

let
  versionData = builtins.fromJSON (builtins.readFile ./hashes.json);
  inherit (versionData) version hash;

  platformMap = {
    x86_64-linux = "bun-linux-x64";
    aarch64-linux = "bun-linux-arm64";
    x86_64-darwin = "bun-darwin-x64";
    aarch64-darwin = "bun-darwin-arm64";
  };

  platform = stdenv.hostPlatform.system;
  bunTarget = platformMap.${platform} or (throw "Unsupported system: ${platform}");
in
stdenv.mkDerivation {
  pname = "plannotator";
  inherit version;

  src = fetchFromGitHub {
    owner = "backnotprop";
    repo = "plannotator";
    tag = "v${version}";
    inherit hash;
  };

  nativeBuildInputs = [
    bun2nix.hook
    bun
    makeWrapper
    python3
  ];

  patches = lib.optionals ((builtins.readFile ./fix-stale-bun-lock.patch) != "") [
    ./fix-stale-bun-lock.patch
  ];

  # Bun's sandboxed install may try to query npm for semver ranges even when
  # bun.lock already records the resolved package. Collapse package.json and
  # bun.lock workspace dependency ranges to the exact versions vendored in
  # bun.nix.
  postPatch = ''
    python3 <<'PY'
    import json
    import re
    from pathlib import Path

    lock_path = Path("bun.lock")
    lock = lock_path.read_text()
    resolved = {}

    for match in re.finditer(r'^    "([^"]+)": \["([^"]+)"', lock, re.MULTILINE):
        name, ref = match.groups()
        prefix = f"{name}@"
        if ref.startswith(prefix):
            version = ref[len(prefix):]
            if not version.startswith("workspace:"):
                resolved[name] = version

    dep_sections = [
        "dependencies",
        "devDependencies",
        "optionalDependencies",
        "peerDependencies",
    ]

    hoisted = {
        "@joplin/turndown-plugin-gfm",
        "@pierre/diffs",
        "@plannotator/webtui",
        "chokidar",
        "parse5",
        "turndown",
    }
    unused = {
        "@opencode-ai/plugin",
        "glimpseui",
    }

    root_package = Path("package.json")

    for package_json in Path(".").glob("**/package.json"):
        if "node_modules" in package_json.parts:
            continue
        data = json.loads(package_json.read_text())
        changed = False

        if package_json == root_package:
            deps = data.setdefault("dependencies", {})
            for name in hoisted:
                if name in resolved and deps.get(name) != resolved[name]:
                    deps[name] = resolved[name]
                    changed = True
        else:
            for section in dep_sections:
                deps = data.get(section)
                if not isinstance(deps, dict):
                    continue
                for name in sorted(hoisted | unused):
                    if name in deps:
                        del deps[name]
                        changed = True

        for section in dep_sections:
            deps = data.get(section)
            if not isinstance(deps, dict):
                continue
            for name, spec in list(deps.items()):
                if isinstance(spec, str) and spec.startswith(("^", "~")) and name in resolved:
                    deps[name] = resolved[name]
                    changed = True
        if changed:
            package_json.write_text(json.dumps(data, indent=2) + "\n")

    def replace_range(match):
        name = match.group(1)
        quote = match.group(2)
        return f'"{name}": {quote}{resolved[name]}{quote}'

    names = "|".join(re.escape(name) for name in sorted(resolved, key=len, reverse=True))
    if names:
        lock = re.sub(
            rf'"({names})": (["\'])[\^~][^"\']+\2',
            replace_range,
            lock,
        )

    removed_names = "|".join(re.escape(name) for name in sorted(hoisted | unused, key=len, reverse=True))
    if removed_names:
        lock = re.sub(
            rf'^        "({removed_names})": "[^"]+",\n',
            "",
            lock,
            flags=re.MULTILINE,
        )

    root_workspace = lock.index('  "": {')
    root_deps_start = lock.index('    "dependencies": {', root_workspace)
    root_deps_end = lock.index('    },', root_deps_start)
    root_deps_block = lock[root_deps_start:root_deps_end]
    additions = ""
    for name in sorted(hoisted):
        if name in resolved and f'"{name}":' not in root_deps_block:
            additions += f'        "{name}": "{resolved[name]}",\n'
    if additions:
        lock = lock[:root_deps_end] + additions + lock[root_deps_end:]

    lock_path.write_text(lock)
    PY
  '';

  bunDeps = bun2nix.fetchBunDeps {
    bunNix = ./bun.nix;
  };

  bunInstallFlags = "--linker=isolated --offline";

  dontUseBunBuild = true;
  dontUseBunInstall = true;
  dontRunLifecycleScripts = true;

  # bun build --compile embeds the JS bundle inside the executable; stripping
  # corrupts it.
  dontStrip = true;

  buildPhase = ''
    runHook preBuild

    mkdir -p .bun-tmp .bun-install
    export BUN_TMPDIR=$PWD/.bun-tmp
    export BUN_INSTALL=$PWD/.bun-install

    bun run build:review
    bun run build:hook
    bun build apps/hook/server/index.ts \
      --compile \
      --no-compile-autoload-bunfig \
      --target=${bunTarget} \
      --define '__CLI_VERSION__="${version}"' \
      --outfile plannotator

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    install -Dm755 plannotator $out/bin/plannotator

    runHook postInstall
  '';

  postFixup = ''
    wrapProgram $out/bin/plannotator \
      --argv0 plannotator \
      --set PLANNOTATOR_SEM_PATH ${lib.getExe plannotatorSem}
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [
    versionCheckHook
    versionCheckHomeHook
  ];
  versionCheckProgramArg = [ "--version" ];

  passthru.category = "Code Review";

  meta = with lib; {
    description = "Interactive plan and code review tool for AI coding agents";
    homepage = "https://github.com/backnotprop/plannotator";
    changelog = "https://github.com/backnotprop/plannotator/releases/tag/v${version}";
    license = with licenses; [
      mit
      asl20
    ];
    sourceProvenance = with sourceTypes; [ fromSource ];
    maintainers = with maintainers; [ nwjsmith ];
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
      "x86_64-darwin"
      "aarch64-darwin"
    ];
    mainProgram = "plannotator";
  };
}
