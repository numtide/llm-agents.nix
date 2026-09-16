{
  bash,
  buildNpmPackage,
  coreutils,
  fetchurl,
  gnugrep,
  gnused,
  jq,
  lib,
  mkUpdater,
  nodejs,
  runCommand,
  versionCheckHook,
  flake,
}:

let
  versionData = lib.importJSON ./hashes.json;
  version = versionData.version;
  # The npm tarball ships no lockfile; add the vendored one for buildNpmPackage.
  # The published package.json also carries repo-only lifecycle scripts
  # (prepack rebuilds from src/, which the tarball does not include), so strip
  # them for the offline build; the shipped dist/ is already built.
  srcWithLock =
    runCommand "yylo-src-with-lock"
      {
        nativeBuildInputs = [ jq ];
      }
      ''
        mkdir -p $out
        tar -xzf ${
          fetchurl {
            url = "https://registry.npmjs.org/@yylo/cli/-/cli-${version}.tgz";
            hash = versionData.sourceHash;
          }
        } -C $out --strip-components=1
        cp ${./package-lock.json} $out/package-lock.json
        jq 'del(.scripts)' $out/package.json > $out/package.json.stripped
        mv $out/package.json.stripped $out/package.json
      '';
in
buildNpmPackage {
  npmDepsFetcherVersion = 2;
  pname = "yylo";
  inherit version;

  src = srcWithLock;

  npmDepsHash = versionData.npmDepsHash;
  makeCacheWritable = true;

  dontNpmBuild = true;

  # The yylo/yy/ypl bins are bash wrappers (yylo.sh / ypl.sh) that exec the
  # real node CLI, so the default node shims would feed bash to node.
  # Wrap them through their shebang with node on PATH; feedback-yylo is a
  # plain .mjs and keeps its default shim.
  postFixup = ''
    wrap() {
      rm -f $out/bin/$1
      makeWrapper $out/lib/node_modules/@yylo/cli/dist/bin/$2 $out/bin/$1 \
        --prefix PATH : ${
          lib.makeBinPath [
            nodejs
            bash
            coreutils
            gnugrep
            gnused
          ]
        }
    }
    wrap yylo yylo.sh
    wrap yy yylo.sh
    wrap ypl ypl.sh
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [ versionCheckHook ];

  passthru.category = "AI Coding Agents";
  passthru.updater = mkUpdater {
    kind = "npm";
    purl = "pkg:npm/@yylo/cli";
  };

  meta = with lib; {
    description = "YYLO (why-lo): task-driven AI subagent orchestration";
    homepage = "https://github.com/yylo-dev/yylo";
    changelog = "https://github.com/yylo-dev/yylo/releases/tag/v${version}";
    license = licenses.mit;
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
    maintainers = with flake.lib.maintainers; [ InsightFactoryAPP ];
    mainProgram = "yylo";
    platforms = platforms.all;
  };
}
