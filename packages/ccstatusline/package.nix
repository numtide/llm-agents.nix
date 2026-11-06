{
  lib,
  stdenv,
  fetchzip,
  nodejs,
  versionCheckHook,
  flake,
}:

stdenv.mkDerivation rec {
  pname = "ccstatusline";
  version = "2.2.34";

  src = fetchzip {
    url = "https://registry.npmjs.org/ccstatusline/-/ccstatusline-${version}.tgz";
    hash = "sha256-YsHIhIH+PECYaznQgzpR3w22t3+yZOCIUnCcowP4CQg=";
  };

  nativeBuildInputs = [ nodejs ];

  installPhase = ''
    runHook preInstall

    # The npm package already contains built files. dist/ is code-split, so
    # keep the whole package together for the entry file's chunk imports.
    mkdir -p $out/libexec/ccstatusline $out/bin
    cp -r --no-preserve=mode $src/. $out/libexec/ccstatusline/
    chmod +x $out/libexec/ccstatusline/dist/ccstatusline.js

    # Replace the shebang with the correct node path
    substituteInPlace $out/libexec/ccstatusline/dist/ccstatusline.js \
      --replace-fail "#!/usr/bin/env node" "#!${nodejs}/bin/node"

    ln -s $out/libexec/ccstatusline/dist/ccstatusline.js $out/bin/ccstatusline

    runHook postInstall
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [ versionCheckHook ];

  passthru.category = "Claude Code Ecosystem";

  meta = with lib; {
    description = "A highly customizable status line formatter for Claude Code CLI";
    homepage = "https://github.com/sirmalloc/ccstatusline";
    changelog = "https://github.com/sirmalloc/ccstatusline/releases/tag/v${version}";
    license = licenses.mit;
    sourceProvenance = with lib.sourceTypes; [ binaryBytecode ];
    maintainers = with flake.lib.maintainers; [ ypares ];
    mainProgram = "ccstatusline";
    platforms = platforms.all;
  };
}
