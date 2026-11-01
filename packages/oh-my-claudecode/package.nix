{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
  flake,
  versionCheckHook,
}:

buildNpmPackage (finalAttrs: {
  npmDepsFetcherVersion = 2;
  pname = "oh-my-claudecode";
  version = "5.7.25";

  src = fetchFromGitHub {
    owner = "yeachan-heo";
    repo = "oh-my-claudecode";
    tag = "v${finalAttrs.version}";
    hash = "sha256-I+M22eVPsSnZpyu+CuCKS23ycJBh8Ct6ZCkSi389j/Y=";
  };

  npmDepsHash = "sha256-HLbyH+Wvs8KIrohVZLwai1fOp+i8OdjDcLs67LRQI7M=";
  makeCacheWritable = true;

  # Native deps (better-sqlite3, @ast-grep/napi) need rebuild skipped
  npmFlags = [ "--ignore-scripts" ];

  doInstallCheck = true;
  nativeInstallCheckInputs = [ versionCheckHook ];

  passthru.category = "Claude Code Ecosystem";

  meta = {
    description = "Multi-agent orchestration system for Claude Code";
    homepage = "https://github.com/yeachan-heo/oh-my-claudecode";
    changelog = "https://github.com/yeachan-heo/oh-my-claudecode/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.mit;
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
    maintainers = with flake.lib.maintainers; [ murlakatam ];
    mainProgram = "oh-my-claudecode";
    platforms = lib.platforms.all;
  };
})
