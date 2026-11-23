{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
  flake,
  makeWrapper,
  pi,
}:

buildNpmPackage rec {
  npmDepsFetcherVersion = 2;
  pname = "pi-acp";
  version = "0.0.35";

  src = fetchFromGitHub {
    owner = "svkozak";
    repo = "pi-acp";
    tag = "v${version}";
    hash = "sha256-/5ga4YEi5GZ95ru+9gDpXp9iWVqmLeInIHddskO4uXg=";
  };

  npmDepsHash = "sha256-tONtExK3DypjZJFnKfkeGpxd1bHJzc02sCdsBxv6XvU=";

  nativeBuildInputs = [ makeWrapper ];

  # The adapter spawns `pi` from PATH.
  postInstall = ''
    wrapProgram $out/bin/pi-acp --prefix PATH : ${lib.makeBinPath [ pi ]}
  '';

  passthru.category = "ACP Ecosystem";

  meta = {
    description = "ACP adapter for the pi coding agent";
    homepage = "https://github.com/svkozak/pi-acp";
    changelog = "https://github.com/svkozak/pi-acp/releases/tag/v${version}";
    license = lib.licenses.mit;
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
    maintainers = with flake.lib.maintainers; [ vidhanio ];
    mainProgram = "pi-acp";
    platforms = lib.platforms.all;
  };
}
