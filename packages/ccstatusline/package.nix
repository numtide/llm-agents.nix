{
  lib,
  stdenv,
  fetchzip,
  nodejs,
  flake,
}:

stdenv.mkDerivation rec {
  pname = "ccstatusline";
  version = "2.0.29";

  src = fetchzip {
    url = "https://registry.npmjs.org/ccstatusline/-/ccstatusline-${version}.tgz";
    hash = "sha256-WfFQPHJa9iGx4M8RxjB/OqRs+UnzHUA7RxQsCRVKxZ0=";
  };

  nativeBuildInputs = [ nodejs ];

  installPhase = ''
    runHook preInstall

    # The npm package already contains built files
    mkdir -p $out/bin
    cp $src/dist/ccstatusline.js $out/bin/ccstatusline
    chmod +x $out/bin/ccstatusline

    # Replace the shebang with the correct node path
    substituteInPlace $out/bin/ccstatusline \
      --replace-quiet "#!/usr/bin/env node" "#!${nodejs}/bin/node"

    runHook postInstall
  '';

  passthru.category = "Claude Code Ecosystem";

  meta = with lib; {
    description = "A highly customizable status line formatter for Claude Code CLI";
    homepage = "https://github.com/sirmalloc/ccstatusline";
    license = licenses.mit;
    sourceProvenance = with lib.sourceTypes; [ binaryBytecode ];
    maintainers = with flake.lib.maintainers; [ ypares ];
    mainProgram = "ccstatusline";
    platforms = platforms.all;
  };
}
