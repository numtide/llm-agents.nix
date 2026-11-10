{
  lib,
  stdenv,
  bash,
  buildGoModule,
  codegraph,
  fetchFromGitHub,
  flake,
  makeWrapper,
  ripgrep,
  bubblewrap,
  versionCheckHook,
  versionCheckHomeHook,
}:

# Upstream rewrote reasonix from TypeScript to Go in 1.0.0.
buildGoModule rec {
  pname = "reasonix";
  version = "2.58.1";

  src = fetchFromGitHub {
    owner = "esengine";
    repo = "DeepSeek-Reasonix";
    tag = "v${version}";
    hash = "sha256-nmuNNI8XmRgR3dLy9IoU0mrBswTzwTCdp3pqPI9/3Uw=";
  };

  vendorHash = "sha256-7i49Vp8aTC23Ak0Oc3oO++ygxxUkczBIOBs6/fSVSNQ=";

  subPackages = [ "cmd/reasonix" ];

  nativeBuildInputs = [ makeWrapper ];

  env.CGO_ENABLED = "0";

  ldflags = [
    "-s"
    "-w"
    "-X main.version=v${version}"
  ];

  doCheck = true;

  doInstallCheck = true;
  nativeInstallCheckInputs = [
    versionCheckHook
    versionCheckHomeHook
  ];

  postFixup = ''
    wrapProgram $out/bin/reasonix \
      --prefix PATH : ${
        lib.makeBinPath (
          [
            bash
            codegraph
            ripgrep
          ]
          ++ lib.optionals stdenv.hostPlatform.isLinux [
            bubblewrap
          ]
        )
      }
  '';

  meta = {
    description = "DeepSeek-native AI coding agent for your terminal";
    homepage = "https://github.com/esengine/DeepSeek-Reasonix";
    license = lib.licenses.mit;
    changelog = "https://github.com/esengine/DeepSeek-Reasonix/releases/tag/v${version}";
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
    maintainers = with flake.lib.maintainers; [ arch-fan ];
    mainProgram = "reasonix";
    platforms = lib.platforms.unix;
  };

  passthru.category = "AI Coding Agents";
}
