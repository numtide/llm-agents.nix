{
  lib,
  flake,
  buildGoModule,
  buildNpmPackage,
  fetchFromGitHub,
  versionCheckHook,
}:

let
  version = "2.0.3";

  src = fetchFromGitHub {
    owner = "Willxup";
    repo = "cpa-usage-keeper";
    tag = "v${version}";
    hash = "sha256-usCeT+84CIhhAK4jIsSjiBazckKR2lc3mE2xI0KVNZQ=";
  };

  frontend = buildNpmPackage {
    pname = "cpa-usage-keeper-frontend";
    inherit version src;
    sourceRoot = "${src.name}/web";
    npmDepsHash = "sha256-C7TcDYjuLxT6fQ4AjnI3gGfp57oqOh9P1ZPJIxi9TVI=";
    npmDepsFetcherVersion = 2;

    installPhase = ''
      runHook preInstall
      cp -r dist $out
      runHook postInstall
    '';
  };
in
buildGoModule {
  pname = "cpa-usage-keeper";
  inherit version src;

  vendorHash = "sha256-kUPQ41UsZX86WNdeYGy914G3Pk/v/WcOfVw8Unb9SE4=";

  subPackages = [ "cmd/server" ];

  ldflags = [
    "-s"
    "-w"
    "-X cpa-usage-keeper/internal/version.Version=v${version}"
  ];

  preBuild = ''
    rm -rf web/dist
    cp -r ${frontend} web/dist
  '';

  postInstall = ''
    mv $out/bin/server $out/bin/cpa-usage-keeper
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [ versionCheckHook ];

  passthru = {
    category = "Usage Analytics";
    inherit frontend;
  };

  meta = {
    description = "Standalone CliProxyAPI usage tracker with SQLite persistence and built-in dashboard";
    homepage = "https://github.com/Willxup/cpa-usage-keeper";
    changelog = "https://github.com/Willxup/cpa-usage-keeper/releases/tag/v${version}";
    license = lib.licenses.mit;
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
    maintainers = with flake.lib.maintainers; [ jiezhuzzz ];
    mainProgram = "cpa-usage-keeper";
    platforms = lib.platforms.unix;
  };
}
