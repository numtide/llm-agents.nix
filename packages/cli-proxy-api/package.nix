{
  lib,
  buildGoModule,
  go_1_26,
  fetchFromGitHub,
  versionCheckHook,
  flake,
}:

buildGoModule.override { go = go_1_26; } rec {
  pname = "cli-proxy-api";
  version = "6.8.18";

  src = fetchFromGitHub {
    owner = "router-for-me";
    repo = "CLIProxyAPI";
    rev = "v${version}";
    hash = "sha256-2cnaO94jfMtxhEtTlv40QnZ9pH62Gpx5mOWTxJ+3r6k=";
  };

  # go.mod may require a newer Go than nixpkgs provides;
  # align the directive with the actual toolchain version.
  postPatch = ''
    sed -i 's/^go .*/go ${go_1_26.version}/' go.mod
  '';

  vendorHash = "sha256-OKZtvLH/CvjKyVWfjMhUdxbhHFJTMz8MqpJm60j71iY=";

  subPackages = [ "cmd/server" ];

  ldflags = [
    "-s"
    "-w"
    "-X main.Version=${version}"
    "-X main.Commit=nixpkgs"
    "-X main.BuildDate=1970-01-01T00:00:00Z"
  ];

  postInstall = ''
    mv $out/bin/server $out/bin/cli-proxy-api
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [ versionCheckHook ];

  passthru.category = "AI Coding Agents";

  meta = with lib; {
    description = "Unified proxy providing OpenAI/Gemini/Claude/Codex compatible APIs for AI coding CLI tools";
    homepage = "https://github.com/router-for-me/CLIProxyAPI";
    changelog = "https://github.com/router-for-me/CLIProxyAPI/releases";
    license = licenses.mit;
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
    maintainers = with flake.lib.maintainers; [ odysseus0 ];
    mainProgram = "cli-proxy-api";
    platforms = platforms.all;
  };
}
