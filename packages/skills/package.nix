{
  buildNpmPackage,
  fetchurl,
  lib,
  runCommand,
  versionCheckHook,
  flake,
}:

let
  versionData = lib.importJSON ./hashes.json;
  version = versionData.version;
  # The npm tarball ships no lockfile; add the vendored one for buildNpmPackage.
  srcWithLock = runCommand "skills-src-with-lock" { } ''
    mkdir -p $out
    tar -xzf ${
      fetchurl {
        url = "https://registry.npmjs.org/skills/-/skills-${version}.tgz";
        hash = versionData.sourceHash;
      }
    } -C $out --strip-components=1
    cp ${./package-lock.json} $out/package-lock.json
  '';
in
buildNpmPackage {
  npmDepsFetcherVersion = 2;
  pname = "skills";
  inherit version;

  src = srcWithLock;

  npmDepsHash = versionData.npmDepsHash;
  makeCacheWritable = true;

  dontNpmBuild = true;

  postFixup = ''
    for bin in skills add-skill; do
      wrapProgram $out/bin/$bin --set DISABLE_TELEMETRY 1
    done
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [ versionCheckHook ];

  passthru.category = "Skills & Plugins";

  meta = with lib; {
    description = "The open agent skills tool for installing and managing skills across AI coding agents";
    homepage = "https://github.com/vercel-labs/skills";
    changelog = "https://github.com/vercel-labs/skills/releases/tag/v${version}";
    license = licenses.mit;
    sourceProvenance = with lib.sourceTypes; [ binaryBytecode ];
    maintainers = with flake.lib.maintainers; [ kusold ];
    mainProgram = "skills";
    platforms = platforms.all;
  };
}
