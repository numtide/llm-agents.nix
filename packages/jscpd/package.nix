{
  lib,
  rustPlatform,
  fetchFromGitHub,
  installAgentSkills,
  pkg-config,
  oniguruma,
  versionCheckHook,
  versionCheckHomeHook,
}:

rustPlatform.buildRustPackage rec {
  pname = "jscpd";
  version = "5.4.3";

  src = fetchFromGitHub {
    owner = "kucherenko";
    repo = "jscpd";
    tag = "v${version}";
    hash = "sha256-ltvWxSJvnnCeRYozMPujFRQy2ADCiGbayzaHiacTEbw=";
  };

  sourceRoot = "${src.name}/rust";

  # nixpkgs' rustc uses LLVM 21, which rejects core::arch's vpdpbusd
  # intrinsic signature; emit the instruction via inline asm instead.
  postPatch = ''
    patch -p1 -d "$cargoDepsCopy/source-registry-0/candle-core-0.11.1" < ${./candle-core-llvm21.patch}
  '';

  cargoHash = "sha256-O7xyseezwHN/g+/q23frE3z9HAUXmnjB4e60USBYWLc=";

  cargoBuildFlags = [
    "-p"
    "jscpd"
  ];

  nativeBuildInputs = [
    installAgentSkills
    pkg-config
  ];

  buildInputs = [ oniguruma ];

  env.RUSTONIG_SYSTEM_LIBONIG = "1";

  dontInstallAgentSkills = true;

  postInstall = ''
    # The Rust source root excludes the sibling skills in the full source tree.
    # Keep their directory names so relative links between skills still work.
    for skill in jscpd dry-refactoring codebase-refactoring compare-codebases code-migration; do
      installSkill "${src}/skills/$skill"
      substituteInPlace "$out/share/skills/jscpd/$skill/SKILL.md" \
        --replace-fail 'npx jscpd' 'jscpd'
    done

    # This inline command is wrapped across two Markdown source lines upstream.
    substituteInPlace "$out/share/skills/jscpd/codebase-refactoring/SKILL.md" \
      --replace-fail $'npx\njscpd --dashboard' 'jscpd --dashboard'
  '';

  # Workspace tests exercise fixtures outside the rust/ source root.
  doCheck = false;

  doInstallCheck = true;
  nativeInstallCheckInputs = [
    versionCheckHook
    versionCheckHomeHook
  ];

  postInstallCheck = ''
    for skill in jscpd dry-refactoring codebase-refactoring compare-codebases code-migration; do
      test -f "$out/share/skills/jscpd/$skill/SKILL.md"
      if grep -F 'npx jscpd' "$out/share/skills/jscpd/$skill/SKILL.md"; then
        echo "Unexpected npm invocation in $skill" >&2
        exit 1
      fi
    done
  '';

  passthru.category = "Code Review";

  meta = {
    description = "Copy/paste detector for programming source code";
    homepage = "https://jscpd.dev";
    changelog = "https://github.com/kucherenko/jscpd/releases/tag/v${version}";
    license = lib.licenses.mit;
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
    maintainers = with lib.maintainers; [ mic92 ];
    mainProgram = "jscpd";
    platforms = lib.platforms.all;
  };
}
