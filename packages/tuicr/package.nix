{
  lib,
  fetchFromGitHub,
  rustPlatform,
  pkg-config,
  installAgentSkills,
  bash,
  libgit2,
  libssh2,
  oniguruma,
  openssl,
  zlib,
  versionCheckHook,
  flake,
}:
rustPlatform.buildRustPackage (finalAttrs: {
  pname = "tuicr";
  version = "0.28.0";

  src = fetchFromGitHub {
    owner = "agavra";
    repo = "tuicr";
    tag = "v${finalAttrs.version}";
    hash = "sha256-Q1VcRGTN3BO/UYTY0/SBN05v/0Dy+iEUNFshHoBjNVM=";
  };

  cargoHash = "sha256-+HbzMHq3OCuF+RCGXaLSbN4+xcFTYyKUI54advFKcEU=";

  nativeBuildInputs = [
    pkg-config
    installAgentSkills
  ];

  buildInputs = [
    bash
    libgit2
    libssh2
    oniguruma
    openssl
    zlib
  ];

  env = {
    LIBSSH2_SYS_USE_PKG_CONFIG = "1";
    LIBZ_SYS_STATIC = "0";
    OPENSSL_NO_VENDOR = "1";
    RUSTONIG_SYSTEM_LIBONIG = "1";
  };

  doCheck = false;

  # Keep the helper beside its wrappers; optional multiplexers remain on PATH.
  dontInstallAgentSkills = true;
  postInstall = ''
    installSkill skills/tuicr
    patchShebangs --host "$out/share/skills/tuicr/tuicr"/tuicr-wrapper*.sh
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [ versionCheckHook ];

  postInstallCheck = ''
    skillDir="$out/share/skills/tuicr/tuicr"
    test -f "$skillDir/SKILL.md"
    test -f "$skillDir/_tuicr-common.sh"
    test ! -x "$skillDir/_tuicr-common.sh"
    for script in tuicr-wrapper{,-cmux,-zellij,-herdr}.sh; do
      test -x "$skillDir/$script"
      grep -Eq '^#!/nix/store/[^ ]+/bin/bash$' "$skillDir/$script"
      grep -Fq "$script" "$skillDir/SKILL.md"
      grep -Fq '/_tuicr-common.sh"' "$skillDir/$script"
      "$skillDir/$script" --help > /dev/null
    done
  '';

  passthru.category = "Code Review";

  meta = {
    description = "Review AI-generated diffs like a GitHub pull request, right from your terminal";
    homepage = "https://github.com/agavra/tuicr";
    changelog = "https://github.com/agavra/tuicr/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.mit;
    mainProgram = "tuicr";
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
    platforms = lib.platforms.unix;
    maintainers = with flake.lib.maintainers; [ ypares ];
  };
})
