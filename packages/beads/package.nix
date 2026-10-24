{
  lib,
  buildGoModule,
  fetchFromGitHub,
  makeWrapper,
  dolt,
  go-bin,
  icu,
  pkg-config,
  versionCheckHook,
}:

buildGoModule.override { go = go-bin; } rec {
  pname = "beads";
  version = "1.3.2";

  src = fetchFromGitHub {
    owner = "gastownhall";
    repo = "beads";
    tag = "v${version}";
    hash = "sha256-f36v59+mSjI0SkwmUditpZwob0tqNosKUrRywEXxUQw=";
  };

  vendorHash = "sha256-akJBtvchASCHKCmzuD77n6WKD/jLN1n01WyyCXXR2xY=";

  nativeBuildInputs = [
    makeWrapper
    pkg-config
  ];

  buildInputs = [
    icu
  ];

  # go-icu-regex's cgo directives use raw -licui18n etc. with no
  # `#cgo pkg-config:` line, so pkg-config never runs. With go-bin (the
  # upstream prebuilt toolchain) on darwin the icu include dir does not
  # make it into the compiler invocation; pass it explicitly so the
  # build is independent of which cc cgo ends up resolving.
  env = {
    CGO_ENABLED = "1";
    CGO_CFLAGS = "-I${lib.getDev icu}/include";
    CGO_CXXFLAGS = "-I${lib.getDev icu}/include";
    CGO_LDFLAGS = "-L${lib.getLib icu}/lib";
  };

  subPackages = [ "cmd/bd" ];

  doCheck = false;

  postInstall = ''
    wrapProgram $out/bin/bd \
      --prefix PATH : ${lib.makeBinPath [ dolt ]}
  '';

  doInstallCheck = true;

  nativeInstallCheckInputs = [ versionCheckHook ];

  passthru.category = "Workflow & Project Management";

  meta = with lib; {
    description = "A distributed issue tracker designed for AI-supervised coding workflows";
    homepage = "https://github.com/gastownhall/beads";
    changelog = "https://github.com/gastownhall/beads/releases/tag/v${version}";
    license = licenses.mit;
    sourceProvenance = with sourceTypes; [ fromSource ];
    maintainers = with maintainers; [ zimbatm ];
    mainProgram = "bd";
    platforms = platforms.unix;
  };
}
