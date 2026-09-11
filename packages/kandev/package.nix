{
  lib,
  flake,
  stdenv,
  stdenvNoCC,
  buildGoModule,
  fetchFromGitHub,
  fetchPnpmDeps,
  pnpmConfigHook,
  pnpm_10,
  fetchurl,
  nodejs_24,
  claude-code,
  codex,
  gemini-cli,
  pi,
  omp,
  opencode,
  copilot-cli,
  hermes-agent,
  amp,
  cursor-agent,
  droid,
  grok,
  kilocode-cli,
  kimi-code,
  qoder-cli,
  qwen-code,
  claudeSupport ? false,
  codexSupport ? false,
  geminiSupport ? false,
  piSupport ? false,
  ompSupport ? false,
  opencodeSupport ? false,
  copilotSupport ? false,
  hermesSupport ? false,
  ampSupport ? false,
  cursorSupport ? false,
  droidSupport ? false,
  grokSupport ? false,
  kilocodeSupport ? false,
  kimiSupport ? false,
  qoderSupport ? false,
  qwenSupport ? false,
  extraPackages ? [ ],
  makeWrapper,
  rcodesign,
  git,
  bash,
  openssh,
  versionCheckHook,
  versionCheckHomeHook,
}:

let
  pname = "kandev";
  version = "0.94.0";

  src = fetchFromGitHub {
    owner = "kdlbs";
    repo = "kandev";
    tag = "v${version}";
    hash = "sha256-9mYY2WlEEjGL8DuQNl2gox097DE3nE18q//xnZbhaqM=";
  };

  runtimeTools = [
    nodejs_24
    git
    bash
    openssh
  ];
  agentRuntimePackages =
    runtimeTools
    ++ lib.optional claudeSupport claude-code
    ++ lib.optional codexSupport codex
    ++ lib.optional geminiSupport gemini-cli
    ++ lib.optional piSupport pi
    ++ lib.optional ompSupport omp
    ++ lib.optional opencodeSupport opencode
    ++ lib.optional copilotSupport copilot-cli
    ++ lib.optional hermesSupport hermes-agent
    ++ lib.optional ampSupport amp
    ++ lib.optional cursorSupport cursor-agent
    ++ lib.optional droidSupport droid
    ++ lib.optional grokSupport grok
    ++ lib.optional kilocodeSupport kilocode-cli
    ++ lib.optional kimiSupport kimi-code
    ++ lib.optional qoderSupport qoder-cli
    ++ lib.optional qwenSupport qwen-code
    ++ extraPackages;
  agentRuntimeCommands = [
    "node"
    "git"
    "bash"
    "ssh"
  ]
  ++ lib.optional claudeSupport "claude"
  ++ lib.optional codexSupport "codex"
  ++ lib.optional geminiSupport "gemini"
  ++ lib.optional piSupport "pi"
  ++ lib.optional ompSupport "omp"
  ++ lib.optional opencodeSupport "opencode"
  ++ lib.optional copilotSupport "copilot"
  ++ lib.optional hermesSupport "hermes"
  ++ lib.optional ampSupport "amp"
  ++ lib.optional cursorSupport "cursor-agent"
  ++ lib.optional droidSupport "droid"
  ++ lib.optional grokSupport "grok"
  ++ lib.optional kilocodeSupport "kilocode"
  ++ lib.optional kimiSupport "kimi"
  ++ lib.optional qoderSupport "qodercli"
  ++ lib.optional qwenSupport "qwen";
  agentPath = lib.makeBinPath agentRuntimePackages;
  # The npm ACP adapters bundle native CLI binaries whose FHS interpreters are
  # unavailable on NixOS. Both adapters honor these overrides and ignore PATH.
  agentRuntimeEnvironment =
    lib.optionalAttrs claudeSupport {
      CLAUDE_CODE_EXECUTABLE = lib.getExe claude-code;
    }
    // lib.optionalAttrs codexSupport {
      CODEX_PATH = lib.getExe codex;
    };
  agentRuntimeWrapperArgs = lib.concatLists (
    lib.mapAttrsToList (name: value: [
      "--set"
      name
      value
    ]) agentRuntimeEnvironment
  );

  pnpm = pnpm_10.overrideAttrs (_: {
    version = "9.15.9";
    src = fetchurl {
      url = "https://registry.npmjs.org/pnpm/-/pnpm-9.15.9.tgz";
      hash = "sha256-z4anrXZEBjldQoam0J1zBxFyCsxtk+nc6ax6xNxKKKc=";
    };
  });

  frontend = stdenvNoCC.mkDerivation (finalAttrs: {
    pname = "kandev-web";
    inherit version src;

    sourceRoot = "${src.name}/apps";

    pnpmDeps = fetchPnpmDeps {
      inherit (finalAttrs)
        pname
        version
        src
        sourceRoot
        ;
      inherit pnpm;
      fetcherVersion = 4;
      hash = "sha256-dH1BWJx4WbN+rmxzhgptlqCTq0boyGWVtDlEo2UCD70=";
    };

    nativeBuildInputs = [
      nodejs_24
      pnpm
      pnpmConfigHook
    ];

    buildPhase = ''
      runHook preBuild
      KANDEV_VERSION=${version} VITE_KANDEV_API_PORT= VITE_KANDEV_DEBUG= \
        pnpm --filter @kandev/web build
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      cp -r web/dist $out
      runHook postInstall
    '';
  });
in
buildGoModule (_finalAttrs: {
  inherit pname version src;

  modRoot = "apps/backend";
  vendorHash = "sha256-jH8w+6A3LO0S+WTtb2K8GKafi83n3HkwOHXeRcOBQKQ=";

  subPackages = [
    "cmd/kandev"
    "cmd/agentctl"
  ];

  tags = [ "fts5" ];

  ldflags = [
    "-s"
    "-w"
    "-X main.Version=v${version}"
  ];

  patches = [ ./prefer-native-acp-runtimes.patch ];

  postPatch = ''
    # Nix sandboxes do not populate FHS bin directories. Preserve the fake curl
    # precedence while letting this upstream test find mktemp and shell tools.
    old_path='"PATH=" + binDir + ":/usr/bin:/bin",'
    sandbox_path='"PATH=" + binDir + ":" + os.Getenv("PATH"),'
    substituteInPlace apps/backend/internal/agent/agents/devin_acp_test.go \
      --replace-fail "$old_path" "$sandbox_path"
  '';

  preBuild = ''
    generated=internal/webapp/embedded/generated
    find "$generated" -mindepth 1 ! -name .gitignore ! -name keep.txt -exec rm -rf {} +
    cp -r ${frontend}/. "$generated/"
  '';

  postBuild = ''
    helper_ldflags="-s -w"
    env CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
      go build -ldflags "$helper_ldflags" -o agentctl-linux-amd64 ./cmd/agentctl
    env CGO_ENABLED=0 GOOS=linux GOARCH=arm64 \
      go build -ldflags "$helper_ldflags" -o agentctl-linux-arm64 ./cmd/agentctl
    env CGO_ENABLED=0 GOOS=darwin GOARCH=arm64 \
      go build -ldflags "$helper_ldflags" -o agentctl-darwin-arm64 ./cmd/agentctl
    env CGO_ENABLED=0 GOOS=darwin GOARCH=amd64 \
      go build -ldflags "$helper_ldflags" -o agentctl-darwin-amd64 ./cmd/agentctl
  '';

  nativeBuildInputs = [
    makeWrapper
    rcodesign
  ];

  postInstall = ''
    mkdir -p $out/libexec/kandev/bin
    mv $out/bin/kandev $out/bin/agentctl $out/libexec/kandev/bin/
    install -Dm755 agentctl-linux-amd64 $out/libexec/kandev/bin/agentctl-linux-amd64
    install -Dm755 agentctl-linux-arm64 $out/libexec/kandev/bin/agentctl-linux-arm64
    install -Dm755 agentctl-darwin-arm64 $out/libexec/kandev/bin/agentctl-darwin-arm64
    install -Dm755 agentctl-darwin-amd64 $out/libexec/kandev/bin/agentctl-darwin-amd64

    makeWrapper $out/libexec/kandev/bin/kandev $out/bin/kandev \
      --set KANDEV_BUNDLE_DIR $out/libexec/kandev \
      --set KANDEV_VERSION ${version} \
      ${lib.escapeShellArgs agentRuntimeWrapperArgs} \
      --prefix PATH : ${agentPath}
  '';

  # Do not let fixup mutate the cross-platform helpers. Re-sign every Darwin
  # binary after fixup because Mach-O mutations invalidate ad-hoc signatures.
  dontStrip = true;

  postFixup = ''
    ${lib.getExe rcodesign} sign --code-signature-flags linker-signed \
      $out/libexec/kandev/bin/agentctl-darwin-arm64
    ${lib.getExe rcodesign} sign --code-signature-flags linker-signed \
      $out/libexec/kandev/bin/agentctl-darwin-amd64
  ''
  + lib.optionalString stdenv.hostPlatform.isDarwin ''
    ${lib.getExe rcodesign} sign --code-signature-flags linker-signed \
      $out/libexec/kandev/bin/kandev
    ${lib.getExe rcodesign} sign --code-signature-flags linker-signed \
      $out/libexec/kandev/bin/agentctl
  '';

  doCheck = true;
  checkPhase = ''
    runHook preCheck
    go test ./internal/agent/agents ./internal/agentctl/server/utility
    runHook postCheck
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [
    versionCheckHook
    versionCheckHomeHook
    nodejs_24
  ];
  versionCheckProgramArg = "--version";

  installCheckPhase = ''
    runHook preInstallCheck

    $out/bin/kandev --help >/dev/null
    ${lib.concatMapStringsSep "\n" (
      package: "grep -aF '${lib.getBin package}/bin' $out/bin/kandev >/dev/null"
    ) agentRuntimePackages}
    for command in ${lib.escapeShellArgs agentRuntimeCommands}; do
      PATH=${agentPath} command -v "$command" >/dev/null
    done
    ${lib.concatStringsSep "\n" (
      lib.mapAttrsToList (name: value: ''
        grep -aF '${name}' $out/bin/kandev >/dev/null
        grep -aF '${value}' $out/bin/kandev >/dev/null
      '') agentRuntimeEnvironment
    )}

    set +e
    output="$($out/libexec/kandev/bin/agentctl kandev 2>&1)"
    status=$?
    set -e
    test "$status" -eq 1
    grep -F "Usage: agentctl kandev" <<<"$output"

    helpers="agentctl-linux-amd64 agentctl-linux-arm64 agentctl-darwin-arm64 agentctl-darwin-amd64"
    for helper in $helpers; do
      test -x "$out/libexec/kandev/bin/$helper"
    done

    node ${src}/scripts/release/validate-darwin-arm64-helper.mjs \
      $out/libexec/kandev/bin/agentctl-darwin-arm64

    runHook postInstallCheck
  '';

  passthru = {
    category = "Workflow & Project Management";
    inherit
      agentPath
      agentRuntimePackages
      agentRuntimeCommands
      agentRuntimeEnvironment
      agentRuntimeWrapperArgs
      frontend
      ;
    agentSupport = {
      inherit
        claudeSupport
        codexSupport
        geminiSupport
        piSupport
        ompSupport
        opencodeSupport
        copilotSupport
        hermesSupport
        ampSupport
        cursorSupport
        droidSupport
        grokSupport
        kilocodeSupport
        kimiSupport
        qoderSupport
        qwenSupport
        ;
    };
  };

  meta = {
    description = "Manage tasks, orchestrate agents, review changes, and ship value";
    homepage = "https://github.com/kdlbs/kandev";
    changelog = "https://github.com/kdlbs/kandev/releases/tag/v${version}";
    license = lib.licenses.agpl3Only;
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
    maintainers = with flake.lib.maintainers; [ mulatta ];
    mainProgram = "kandev";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
      "aarch64-darwin"
    ];
  };
})
