{
  lib,
  fetchFromGitHub,
  rustPlatform,
  makeWrapper,
  jq,
  pkg-config,
  sqlite,
}:

rustPlatform.buildRustPackage rec {
  pname = "rtk";
  version = "1.2.0";

  src = fetchFromGitHub {
    owner = "rtk-ai";
    repo = "rtk";
    tag = "v${version}";
    hash = "sha256-dkMae+wh/W0qytr5AyRbibmrGMtIous88Asq13FLnjI=";
  };

  cargoHash = "sha256-0VUc3Se3MdmffCkbCw2esLnmht9ZhwnmVCqxjudElfA=";

  nativeBuildInputs = [
    makeWrapper
    pkg-config
  ];

  buildInputs = [ sqlite ];

  env.LIBSQLITE3_SYS_USE_PKG_CONFIG = "1";

  doCheck = false;

  postInstall = ''
    mkdir -p $out/libexec/rtk
    cp -r $src/hooks $out/libexec/rtk/hooks
    chmod -R +w $out/libexec/rtk/hooks
    find $out/libexec/rtk/hooks -name '*.sh' -exec chmod 755 {} \;
    for f in $(find $out/libexec/rtk/hooks -name '*.sh'); do
      wrapProgram "$f" \
        --prefix PATH : ${lib.makeBinPath [ jq ]}:$out/bin
    done
  '';

  passthru.category = "Utilities";

  meta = with lib; {
    description = "CLI proxy that reduces LLM token consumption by 60-90% on common dev commands";
    homepage = "https://github.com/rtk-ai/rtk";
    changelog = "https://github.com/rtk-ai/rtk/releases/tag/v${version}";
    license = licenses.mit;
    sourceProvenance = with sourceTypes; [ fromSource ];
    maintainers = with maintainers; [ vizid ];
    mainProgram = "rtk";
    platforms = platforms.unix;
  };
}
