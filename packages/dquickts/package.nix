{
  lib,
  stdenv,
  fetchFromGitHub,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "dquickts";
  version = "0-unstable-2026-10-28";

  src = fetchFromGitHub {
    owner = "stencil-hq";
    repo = "dquickts";
    rev = "8beb2f00a19f0caafef7eb69fe16fa70916d44c1";
    hash = "sha256-80lIeHS/SQN3FZTbAPzr+CRjMfMQYAgoa+JD6fcmK3o=";
  };

  makeFlags = [
    "PREFIX=${placeholder "out"}"
    "CC=${stdenv.cc.targetPrefix}cc"
    "QJSC_CC=${stdenv.cc}/bin/${stdenv.cc.targetPrefix}cc"
  ];

  doCheck = true;
  checkTarget = [
    "test"
    "test-snapshot"
  ];
  enableParallelBuilding = true;

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    "$out/bin/qjs" --typescript -e 'const answer: number = 42; if (answer !== 42) throw new Error("TypeScript")'
    executable="$TMPDIR/${finalAttrs.pname}-hello"
    "$out/bin/qjsc" -o "$executable" "$src/examples/hello.js"
    output=$("$executable")
    test "$output" = "Hello World"
    runHook postInstallCheck
  '';

  passthru.category = "Utilities";

  meta = {
    description = "QuickJS with durable execution and native TypeScript";
    homepage = "https://github.com/stencil-hq/dquickts";
    changelog = "https://github.com/stencil-hq/dquickts/blob/${finalAttrs.src.rev}/Changelog";
    license = lib.licenses.mit;
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
    maintainers = with lib.maintainers; [ ryoppippi ];
    mainProgram = "qjs";
    platforms = [
      "aarch64-darwin"
      "aarch64-linux"
      "x86_64-linux"
    ];
  };
})
