{
  lib,
  stdenv,
  fetchzip,
  nodejs,
  flake,
}:

let
  versionData = lib.importJSON ./hashes.json;
in
stdenv.mkDerivation rec {
  pname = "skills-installer";
  inherit (versionData) version;

  src = fetchzip {
    url = "https://registry.npmjs.org/${pname}/-/${pname}-${version}.tgz";
    inherit (versionData) hash;
  };

  nativeBuildInputs = [ nodejs ];

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin
    cp $src/dist/cli.js $out/bin/skills-installer
    chmod +x $out/bin/skills-installer

    substituteInPlace $out/bin/skills-installer \
      --replace-quiet "#!/usr/bin/env node" "#!${nodejs}/bin/node"

    runHook postInstall
  '';

  passthru.category = "Claude Code Ecosystem";

  meta = with lib; {
    description = "Install agent skills across multiple AI coding clients";
    homepage = "https://github.com/Kamalnrf/claude-plugins";
    changelog = "https://github.com/Kamalnrf/claude-plugins/releases";
    license = licenses.mit;
    sourceProvenance = with lib.sourceTypes; [ binaryBytecode ];
    maintainers = with flake.lib.maintainers; [ ypares ];
    mainProgram = "skills-installer";
    platforms = platforms.all;
  };
}
