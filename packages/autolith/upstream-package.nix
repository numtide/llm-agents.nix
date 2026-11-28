{
  pkgs,
  src,
  crane,
  # Packagers that ship Autolith under another name set these defaults in the
  # launcher. Nonempty AUTOLITH_* environment variables override these defaults.
  directoryName ? null,
  productName ? null,
  commandName ? null,
  siteConfigRoot ? null,
}:

let
  lib = pkgs.lib;
  inherit (pkgs.stdenv.hostPlatform.extensions) sharedLibrary;
  colorlispSharedLibraryFlag = if pkgs.stdenv.hostPlatform.isDarwin then "-dynamiclib" else "-shared";
  minimumSbclVersion = lib.removeSuffix "\n" (builtins.readFile "${src}/sbcl-minimum.version");
  fffSourceCommit = "9a7b1c8fc1d20236a255bf3ddb24eeb761bd6bd9";

  # Git dependencies come from qlfile.lock, the same lock qlot installs from,
  # so Nix never carries a second copy of a ref. The lock records each git
  # source as
  #   ("name" . (:class qlot/source/git:source-git
  #              :initargs (:remote-url "URL" :ref "SHA") :version "git-SHA"))
  # and builtins.fetchGit pins the checkout by that full commit, which pure
  # evaluation accepts without a separate hash. The fetched tree is a
  # content-addressed store path, so every derivation built from it stays
  # binary-cacheable; only the first evaluation on a machine clones.
  qlotLock = builtins.readFile "${src}/qlfile.lock";
  qlotGitSources =
    let
      pattern = ''\("([^"]+)" \.[[:space:]]+\(:class qlot/source/git:source-git[[:space:]]+:initargs \(:remote-url "([^"]+)" :ref "([0-9a-f]{40})"\)'';
      matches = builtins.filter builtins.isList (builtins.split pattern qlotLock);
    in
    builtins.listToAttrs (
      map (match: {
        name = builtins.elemAt match 0;
        value = {
          url = builtins.elemAt match 1;
          rev = builtins.elemAt match 2;
        };
      }) matches
    );
  qlotEntry =
    name:
    qlotGitSources.${name}
      or (throw "qlfile.lock has no git source named ${name}; add it to the qlfile and run ./script/bootstrap.");
  qlotSource =
    name:
    let
      entry = qlotEntry name;
    in
    builtins.fetchGit {
      inherit (entry) url rev;
      allRefs = true;
    };
  qlotVersion = name: "git-${builtins.substring 0 12 (qlotEntry name).rev}";

  # Every git source in the lock must have build metadata below. A dependency
  # added to the qlfile without a buildASDFSystem entry fails evaluation here
  # instead of quietly shipping a release that never loaded it.
  qlotLibrariesWithBuildMetadata = [
    "agentcomms"
    "argo"
    "cl+ssl"
    "cl-colorist"
    "cl-exec-sandbox"
    "cl-hashline"
    "cl-jobpond"
    "cl-llm-provider-api"
    "cl-lsp"
    "cl-resources"
    "cl-rfc8252"
    "cl-rfc8628"
    "cl-skills"
    "cl-termdown"
    "cl-worktree"
    "clasted"
    "clermaid"
    "clifff"
    "clinedi"
    "clinker-transcript"
    "colordiff"
    "colorlisp"
    "daphne"
    "defingerprinter"
    "fetch-gist"
    "idsmall"
    "image-daemon"
    "lambda-debugger"
    "lisp-em"
    "llh2"
    "ls-compat"
    "ls-flock"
    "mcparen"
    "org-templater"
    "parenchek"
    "prezdivka"
    "sbcl-generations"
    "sbcl-workers"
    "setinka"
    "sexp-config"
    "sexp-store"
    "sito"
    "sophisticated-clipboard"
    "structlisp"
    "surgeon"
    "yolokuva"
  ];
  qlotSourcesWithoutBuildMetadata = lib.subtractLists qlotLibrariesWithBuildMetadata (
    builtins.attrNames qlotGitSources
  );

  # Override the package scope so Dexador and every other transitive consumer
  # use the locked CL+SSL source, rather than a second Quicklisp copy.
  lispPackages = pkgs.sbclPackages.overrideScope (
    _final: previous: {
      cl_plus_ssl = previous.cl_plus_ssl.overrideAttrs {
        version = qlotVersion "cl+ssl";
        src = qlotSource "cl+ssl";
      };
    }
  );

  # Quicklisp's NYAML archive includes dangling symlinks in its unused test data.
  nyaml = lispPackages.nyaml.overrideAttrs (old: {
    postInstall = (old.postInstall or "") + ''
      rm -rf "$out/test/yaml-test-suite-data"
    '';
  });

  defingerprinterSource = qlotSource "defingerprinter";
  defingerprinter = pkgs.sbcl.buildASDFSystem {
    pname = "defingerprinter";
    version = qlotVersion "defingerprinter";
    src = defingerprinterSource;
    lispLibs = with pkgs.sbclPackages; [
      cffi
      babel
      bordeaux-threads
    ];
  };

  # Import upstream packaging from the same locked checkout as the Lisp binding.
  # Loading the ASDF system does not load this library or initialize its model.
  defingerprinterSupported = builtins.elem pkgs.stdenv.hostPlatform.system [
    "aarch64-darwin"
    "aarch64-linux"
    "x86_64-linux"
  ];
  defingerprinterPackages =
    (import "${defingerprinterSource}/nix/default.nix" {
      inherit crane;
    })
      { inherit pkgs; };
  defingerprinterNative =
    if defingerprinterSupported then defingerprinterPackages.packages.default else null;

  defingerprinterChecks =
    pkgs.runCommand "autolith-defingerprinter-checks"
      {
        nativeBuildInputs = [ (pkgs.sbcl.withPackages (_: [ defingerprinter ])) ];
      }
      ''
        export HOME="$TMPDIR/home"
        mkdir -p "$HOME"
        export DEFINGERPRINTER_LIBRARY="${defingerprinterNative.lib}/lib/libdefingerprinter${sharedLibrary}"
        # ASDF loading must not open the native library before explicit consent.
        sbcl --noinform --no-sysinit --no-userinit --non-interactive \
          --eval '(require :asdf)' \
          --eval '(asdf:load-system :defingerprinter)' \
          --eval '(assert (null defingerprinter::*library*))' \
          --eval '(assert (null defingerprinter::*library-path*))' \
          --load "${defingerprinterSource}/tests/cffi.lisp" \
          --eval '(defingerprinter-tests:run-tests)'
        touch "$out"
      '';

  agentcomms = pkgs.sbcl.buildASDFSystem {
    pname = "agentcomms";
    version = qlotVersion "agentcomms";
    src = qlotSource "agentcomms";
    lispLibs = [
      argo
      llh2
      lsCompat
    ]
    ++ (with lispPackages; [
      babel
      bordeaux-threads
      cl-base64
      ironclad
      serapeum
      usocket
    ]);
  };

  llh2 = pkgs.sbcl.buildASDFSystem {
    pname = "llh2";
    version = qlotVersion "llh2";
    src = qlotSource "llh2";
    systems = [ "llh2" ];
    lispLibs = with lispPackages; [
      bordeaux-threads
      cl-base64
      serapeum
    ];
  };

  clColorist = pkgs.sbcl.buildASDFSystem {
    pname = "cl-colorist";
    version = qlotVersion "cl-colorist";
    src = qlotSource "cl-colorist";
  };

  clLlmProviderApi = pkgs.sbcl.buildASDFSystem {
    pname = "cl-llm-provider-api";
    version = qlotVersion "cl-llm-provider-api";
    systems = [
      "cl-llm-provider-api"
      "cl-llm-provider-api/wire"
      "cl-llm-provider-api/dexador"
      "cl-llm-provider-api/context"
      "cl-llm-provider-api/contracts"
      "cl-llm-provider-api/registry"
    ];
    src = qlotSource "cl-llm-provider-api";
    lispLibs = with lispPackages; [
      argo
      babel
      bordeaux-threads
      ironclad
      yason
      dexador
      cl_plus_ssl
      usocket
      clinkerTranscript
      clRfc8628
    ];
  };

  clLsp = pkgs.sbcl.buildASDFSystem {
    pname = "cl-lsp";
    version = qlotVersion "cl-lsp";
    src = qlotSource "cl-lsp";
    lispLibs = [
      argo
      sexpConfig
    ]
    ++ (with lispPackages; [
      bordeaux-threads
      quri
      serapeum
    ]);
  };

  clRfc8252 = pkgs.sbcl.buildASDFSystem {
    pname = "cl-rfc8252";
    version = qlotVersion "cl-rfc8252";
    src = qlotSource "cl-rfc8252";
    lispLibs = [
      clRfc8628
    ]
    ++ (with lispPackages; [
      babel
      cl-base64
      ironclad
      quri
      usocket
    ]);
  };
  clRfc8628 = pkgs.sbcl.buildASDFSystem {
    pname = "cl-rfc8628";
    version = qlotVersion "cl-rfc8628";
    src = qlotSource "cl-rfc8628";
    lispLibs = with lispPackages; [
      bordeaux-threads
      cl-base64
      dexador
      quri
      yason
    ];
  };

  clinkerTranscript = pkgs.sbcl.buildASDFSystem {
    pname = "clinker-transcript";
    version = qlotVersion "clinker-transcript";
    src = qlotSource "clinker-transcript";
    lispLibs = with lispPackages; [
      yason
      structlisp
    ];
  };

  lambdaDebugger = pkgs.sbcl.buildASDFSystem {
    pname = "lambda-debugger";
    version = qlotVersion "lambda-debugger";
    src = qlotSource "lambda-debugger";
    lispLibs = [ lispPackages.trivial-gray-streams ];
  };

  imageDaemon = pkgs.sbcl.buildASDFSystem {
    pname = "image-daemon";
    version = qlotVersion "image-daemon";
    src = qlotSource "image-daemon";
    systems = [
      "image-daemon"
      "image-daemon/runtime"
      "image-daemon/eval"
      "image-daemon/messages"
    ];
    lispLibs = [
      idsmall
      lispPackages.ironclad
      lispPackages.bordeaux-threads
      lispPackages.serapeum
      lsCompat
      lsFlock
      sexpConfig
      sexpStore
      structlisp
      lispPackages.trivial-gray-streams
    ];
  };

  argo = pkgs.sbcl.buildASDFSystem {
    pname = "argo";
    version = qlotVersion "argo";
    src = qlotSource "argo";
    lispLibs = with lispPackages; [
      flexi-streams
      serapeum
      yason
    ];
  };

  setinka = pkgs.sbcl.buildASDFSystem {
    pname = "setinka";
    version = qlotVersion "setinka";
    src = qlotSource "setinka";
    lispLibs = with lispPackages; [
      bordeaux-threads
      serapeum
    ];
  };

  lsCompat = pkgs.sbcl.buildASDFSystem {
    pname = "ls-compat";
    version = qlotVersion "ls-compat";
    src = qlotSource "ls-compat";
    systems = [
      "ls-compat"
      "ls-compat/posix"
      "ls-compat/files"
      "ls-compat/tcp"
    ];
    lispLibs = with lispPackages; [
      babel
      serapeum
      usocket
    ];
  };

  lsFlock = pkgs.sbcl.buildASDFSystem {
    pname = "ls-flock";
    version = qlotVersion "ls-flock";
    src = qlotSource "ls-flock";
    lispLibs = with lispPackages; [
      bordeaux-threads
    ];
  };

  clSkills = pkgs.sbcl.buildASDFSystem {
    pname = "cl-skills";
    version = qlotVersion "cl-skills";
    src = qlotSource "cl-skills";
    systems = [
      "cl-skills"
      "cl-skills/executable"
    ];
    lispLibs = [
      clLlmProviderApi
      lispPackages.ironclad
      lsCompat
      nyaml
      lispPackages.serapeum
      sexpConfig
    ];
  };

  clinedi = pkgs.sbcl.buildASDFSystem {
    pname = "clinedi";
    version = qlotVersion "clinedi";
    src = qlotSource "clinedi";
    systems = [
      "clinedi"
      "clinedi/posix"
      "clinedi/lisp-layout"
    ];
    lispLibs = [
      clColorist
      parenchek
    ]
    ++ (with lispPackages; [
      bordeaux-threads
      trivial-gray-streams
    ]);
  };

  mcparen = pkgs.sbcl.buildASDFSystem {
    pname = "mcparen";
    version = qlotVersion "mcparen";
    src = qlotSource "mcparen";
    systems = [
      "mcparen"
      "mcparen/managed"
    ];
    lispLibs = [
      argo
      lsCompat
    ]
    ++ (with lispPackages; [
      babel
      bordeaux-threads
      dexador
      quri
      serapeum
    ]);
  };

  colorlispSource = qlotSource "colorlisp";

  colorlispNativeLibrary = pkgs.stdenv.mkDerivation {
    pname = "colorlisp-tree-sitter";
    version = qlotVersion "colorlisp";
    src = colorlispSource;
    nativeBuildInputs = [ pkgs.sbcl ];
    dontConfigure = true;
    buildPhase = ''
      runHook preBuild
      sbcl --noinform --disable-debugger --script script/build-native.lisp \
        shared "$PWD/libcolorlisp-tree-sitter${sharedLibrary}" \
        "$CC" "$AR" "${colorlispSharedLibraryFlag}"
      runHook postBuild
    '';
    installPhase = ''
      runHook preInstall
      install -Dm755 libcolorlisp-tree-sitter${sharedLibrary} \
        "$out/lib/libcolorlisp-tree-sitter${sharedLibrary}"
      runHook postInstall
    '';
  };

  colorlisp = pkgs.sbcl.buildASDFSystem {
    pname = "colorlisp";
    version = qlotVersion "colorlisp";
    src = colorlispSource;
    lispLibs = with lispPackages; [
      babel
      cffi
      cl-ppcre
    ];
  };

  colordiff = pkgs.sbcl.buildASDFSystem {
    pname = "colordiff";
    version = qlotVersion "colordiff";
    src = qlotSource "colordiff";
    lispLibs = [
      clColorist
      colorlisp
    ];
  };

  clermaid = pkgs.sbcl.buildASDFSystem {
    pname = "clermaid";
    version = qlotVersion "clermaid";
    src = qlotSource "clermaid";
    lispLibs = [ clinedi ];
  };

  lispEm = pkgs.sbcl.buildASDFSystem {
    pname = "lisp-em";
    version = qlotVersion "lisp-em";
    src = qlotSource "lisp-em";
    systems = [ "lisp-em" ];
    lispLibs = [
      argo
      lispPackages.cl-base64
    ];
  };

  clTermdown = pkgs.sbcl.buildASDFSystem {
    pname = "cl-termdown";
    version = qlotVersion "cl-termdown";
    src = qlotSource "cl-termdown";
    lispLibs = with lispPackages; [
      clinedi
      clermaid
      colordiff
      colorlisp
      serapeum
    ];
  };

  parenchek = pkgs.sbcl.buildASDFSystem {
    pname = "parenchek";
    version = qlotVersion "parenchek";
    src = qlotSource "parenchek";
    lispLibs = [
      lsCompat
    ]
    ++ (with lispPackages; [
      serapeum
    ]);
  };

  orgTemplater = pkgs.sbcl.buildASDFSystem {
    pname = "org-templater";
    version = qlotVersion "org-templater";
    src = qlotSource "org-templater";
  };

  structlisp = pkgs.sbcl.buildASDFSystem {
    pname = "structlisp";
    version = qlotVersion "structlisp";
    src = qlotSource "structlisp";
  };

  clHashline = pkgs.sbcl.buildASDFSystem {
    pname = "cl-hashline";
    version = qlotVersion "cl-hashline";
    src = qlotSource "cl-hashline";
    systems = [ "cl-hashline" ];
    lispLibs = [
      structlisp
    ]
    ++ (with lispPackages; [
      babel
      ironclad
    ]);
  };

  clifff = pkgs.sbcl.buildASDFSystem {
    pname = "clifff";
    version = qlotVersion "clifff";
    src = qlotSource "clifff";
    lispLibs = with lispPackages; [
      bordeaux-threads
      cffi
    ];
  };

  sexpStore = pkgs.sbcl.buildASDFSystem {
    pname = "sexp-store";
    version = qlotVersion "sexp-store";
    src = qlotSource "sexp-store";
    lispLibs = [
      lsCompat
      lsFlock
      sexpConfig
    ];
  };

  sbclWorkers = pkgs.sbcl.buildASDFSystem {
    pname = "sbcl-workers";
    version = qlotVersion "sbcl-workers";
    src = qlotSource "sbcl-workers";
    systems = [
      "sbcl-workers"
      "sbcl-workers/host-callbacks"
    ];
    lispLibs = [
      lsCompat
      sexpStore
    ]
    ++ (with lispPackages; [
      bordeaux-threads
      trivial-gray-streams
    ]);
  };

  yolokuva = pkgs.sbcl.buildASDFSystem {
    pname = "yolokuva";
    version = qlotVersion "yolokuva";
    src = qlotSource "yolokuva";
    systems = [
      "yolokuva"
      "yolokuva/opticl"
    ];
    lispLibs = with lispPackages; [ opticl ];
  };

  surgeon = pkgs.sbcl.buildASDFSystem {
    pname = "surgeon";
    version = qlotVersion "surgeon";
    src = qlotSource "surgeon";
    lispLibs = [
      lsCompat
    ]
    ++ (with lispPackages; [
      closer-mop
      serapeum
    ]);
  };

  idsmall = pkgs.sbcl.buildASDFSystem {
    pname = "idsmall";
    version = qlotVersion "idsmall";
    src = qlotSource "idsmall";
    lispLibs = with lispPackages; [ bordeaux-threads ];
  };

  prezdivka = pkgs.sbcl.buildASDFSystem {
    pname = "prezdivka";
    version = qlotVersion "prezdivka";
    src = qlotSource "prezdivka";
  };

  sito = pkgs.sbcl.buildASDFSystem {
    pname = "sito";
    version = qlotVersion "sito";
    src = qlotSource "sito";
  };

  sexpConfig = pkgs.sbcl.buildASDFSystem {
    pname = "sexp-config";
    version = qlotVersion "sexp-config";
    src = qlotSource "sexp-config";
  };

  sophisticatedClipboard = pkgs.sbcl.buildASDFSystem {
    pname = "sophisticated-clipboard";
    version = qlotVersion "sophisticated-clipboard";
    src = qlotSource "sophisticated-clipboard";
    lispLibs = with lispPackages; [
      cl-base64
      flexi-streams
    ];
  };

  sbclGenerations = pkgs.sbcl.buildASDFSystem {
    pname = "sbcl-generations";
    version = qlotVersion "sbcl-generations";
    src = qlotSource "sbcl-generations";
    lispLibs = with lispPackages; [
      bordeaux-threads
      ironclad
    ];
  };

  clJobpond = pkgs.sbcl.buildASDFSystem {
    pname = "cl-jobpond";
    version = qlotVersion "cl-jobpond";
    src = qlotSource "cl-jobpond";
    systems = [
      "cl-jobpond"
      "cl-jobpond/durable-state"
      "cl-jobpond/schedules"
      "cl-jobpond/mailboxes"
      "cl-jobpond/completions"
    ];
    lispLibs = with lispPackages; [ bordeaux-threads ];
  };

  clResources = pkgs.sbcl.buildASDFSystem {
    pname = "cl-resources";
    version = qlotVersion "cl-resources";
    src = qlotSource "cl-resources";
    lispLibs = with lispPackages; [
      babel
      bordeaux-threads
    ];
  };

  clWorktree = pkgs.sbcl.buildASDFSystem {
    pname = "cl-worktree";
    version = qlotVersion "cl-worktree";
    src = qlotSource "cl-worktree";
  };

  clasted = pkgs.sbcl.buildASDFSystem {
    pname = "clasted";
    version = qlotVersion "clasted";
    src = qlotSource "clasted";
    systems = [
      "clasted"
      "clasted/ast-grep"
    ];
    lispLibs = [
      argo
    ]
    ++ (with lispPackages; [
      babel
      ironclad
    ]);
  };

  daphne = pkgs.sbcl.buildASDFSystem {
    pname = "daphne";
    version = qlotVersion "daphne";
    src = qlotSource "daphne";
    lispLibs = [
      argo
    ]
    ++ (with lispPackages; [
      babel
      bordeaux-threads
    ]);
  };

  clExecSandboxSource = qlotSource "cl-exec-sandbox";

  clExecSandbox = pkgs.sbcl.buildASDFSystem {
    pname = "cl-exec-sandbox";
    version = qlotVersion "cl-exec-sandbox";
    src = clExecSandboxSource;
  };

  # Full-access execution on Linux and macOS still needs process-group supervision.
  # Linux also builds the sandbox helper for seccomp and network namespaces;
  # macOS sandboxing uses the system Seatbelt backend instead.
  sandboxHelper = pkgs.stdenv.mkDerivation {
    pname = "cl-exec-sandbox-helper";
    version = "0.1.0";
    src = clExecSandboxSource;
    nativeBuildInputs = [ pkgs.bash ];
    dontConfigure = true;
    buildPhase = ''
      runHook preBuild
      bash scripts/build-helper
      runHook postBuild
    '';
    installPhase = ''
      runHook preInstall
      install -Dm755 build/cl-exec-sandbox-process-group \
        "$out/libexec/cl-exec-sandbox-process-group"
      ${lib.optionalString pkgs.stdenv.hostPlatform.isLinux ''
        install -Dm755 build/cl-exec-sandbox-helper \
          "$out/libexec/cl-exec-sandbox-helper"
      ''}
      runHook postInstall
    '';
  };

  fffLibrary = pkgs.rustPlatform.buildRustPackage {
    pname = "fff-c";
    version = "unstable-${builtins.substring 0 7 fffSourceCommit}";
    src = pkgs.fetchFromGitHub {
      owner = "dmtrKovalenko";
      repo = "fff";
      rev = fffSourceCommit;
      hash = "sha256-CKWthCiJzsonqqwrEacooZx6p1PbfXzWKprrartPfcQ=";
    };
    cargoHash = "sha256-v9Bqp7kXtMPwTaoyiaMZA47AUjAN3EkCeSa94JWauyA=";
    cargoBuildFlags = [
      "-p"
      "fff-c"
    ];
    cargoTestFlags = [
      "-p"
      "fff-c"
    ];
    nativeBuildInputs = [
      pkgs.cmake
      pkgs.pkg-config
    ];
    buildInputs = [ pkgs.zlib ];
    installPhase = ''
      runHook preInstall
      install -Dm755 \
        "$(find target -type f -name 'libfff_c${sharedLibrary}' -print -quit)" \
        "$out/lib/libfff_c${sharedLibrary}"
      runHook postInstall
    '';
  };

  fetchGist = pkgs.sbcl.buildASDFSystem {
    pname = "fetch-gist";
    version = qlotVersion "fetch-gist";
    src = qlotSource "fetch-gist";
    lispLibs = with lispPackages; [
      dexador
      plump
    ];
  };

  autolithSystem = pkgs.sbcl.buildASDFSystem {
    pname = "autolith";
    version = lib.removeSuffix "\n" (builtins.readFile "${src}/VERSION");
    inherit src;
    systems = [
      "autolith"
      "autolith/structural"
      "autolith/debug"
    ];
    lispLibs = with lispPackages; [
      agentcomms
      argo
      bordeaux-threads
      cl-base64
      cffi
      clingon
      closer-mop
      colorlisp
      colordiff
      clTermdown
      lispEm
      dexador
      defingerprinter
      fetchGist
      ironclad
      parenchek
      orgTemplater
      quri
      serapeum
      alexandria
      split-sequence
      trivial-gray-streams
      clColorist
      clinedi
      clExecSandbox
      clHashline
      clifff
      clinkerTranscript
      clJobpond
      clLlmProviderApi
      clLsp
      clResources
      clRfc8252
      clRfc8628
      clSkills
      clWorktree
      clasted
      daphne
      idsmall
      imageDaemon
      lambdaDebugger
      lsCompat
      lsFlock
      mcparen
      prezdivka
      sbclGenerations
      sbclWorkers
      setinka
      sito
      sexpConfig
      sexpStore
      sophisticatedClipboard
      structlisp
      surgeon
      yolokuva
    ];
    nativeBuildInputs = [ pkgs.git ];

    postInstall = ''
      # Detached sessions execute the source launcher directly, without the wrapper.
      substituteInPlace "$out/bin/autolith" \
        --replace-fail '#!/usr/bin/env bash' '#!${pkgs.bash}/bin/bash'

      # Upstream launchers load .qlot/setup.lisp. Map that tiny interface to
      # the Nix-provided ASDF registry so startup and image builds stay offline.
      mkdir -p "$out/.qlot"
      cat > "$out/.qlot/setup.lisp" <<'LISP'
      (require :asdf)
      ;; Match the ASDF used to compile the Nix-provided dependency FASLs.
      (load (uiop:getenv "ASDF"))
      (let* ((source-root (uiop:getenv "AUTOLITH_NIX_SOURCE_ROOT"))
             (cache-root  (uiop:getenv "AUTOLITH_ASDF_CACHE")))
        (when (and source-root cache-root)
          (let* ((source
                   (uiop:ensure-directory-pathname source-root))
                 (configuration
                   (asdf/output-translations:parse-output-translations-string
                    (uiop:getenv "ASDF_OUTPUT_TRANSLATIONS")))
                 (entry
                   (find-if
                    (lambda (candidate)
                      (and (consp candidate)
                           (stringp (first candidate))
                           (uiop:pathname-equal
                            source
                            (uiop:ensure-directory-pathname
                             (first candidate)))))
                    (rest configuration))))
            (unless entry
              (error "No Nix ASDF mapping exists for ~A" source-root))
            (setf (second entry) (format nil "~A//" cache-root))
            (asdf:initialize-output-translations configuration))))
      (defpackage #:ql
        (:use #:cl)
        (:export #:quickload))
      (in-package #:ql)
      (defun quickload (system &key silent &allow-other-keys)
        (declare (ignore silent))
        (asdf:load-system system))
      LISP

      rm -f "$out/.gitignore"
      cp ${src}/.gitignore "$out/.gitignore"
      chmod u+w "$out/.gitignore"
      printf '\n/nix-support/\n' >> "$out/.gitignore"

      # Autolith records source provenance with Git. Flake source archives do
      # not contain .git, so create a deterministic, read-only repository.
      git init --quiet --initial-branch=master "$out"
      git -C "$out" config user.name "Autolith Nix build"
      git -C "$out" config user.email "nix-build@localhost"
      git -C "$out" config gc.auto 0
      git -C "$out" config maintenance.auto false
      git -C "$out" add --all
      GIT_AUTHOR_DATE='2000-01-01T00:00:00Z' \
        GIT_COMMITTER_DATE='2000-01-01T00:00:00Z' \
        git -C "$out" commit --quiet --message "Autolith source"

      # A stat-less index does not need refreshing when Git reads it from the
      # immutable Nix store at runtime.
      rm "$out/.git/index"
      git -C "$out" read-tree HEAD

      # Pack synchronously before Nix scans the output. Background maintenance
      # can otherwise remove loose objects during the fixup phase.
      git -C "$out" gc --quiet --prune=now
    '';
  };

  imageIdentity = pkgs.writeText "autolith-image-identity" ''
    ${autolithSystem}
  '';

  # The test system and FiveAM are development dependencies. Only the flake's
  # checks load them, from this variant, so the package never contains them.
  autolithTests = autolithSystem.overrideLispAttrs (old: {
    pname = "autolith-tests";
    systems = old.systems ++ [ "autolith/tests" ];
    lispLibs = old.lispLibs ++ (with lispPackages; [ fiveam ]);
  });

  testRuntime = pkgs.sbcl.withPackages (_: [ autolithTests ]);

  # Include the trusted native path in SBCL launches as well as the CLI, so
  # workers and checks inherit it without enabling diagnostics consent.
  runtime = (pkgs.sbcl.withPackages (_: [ autolithSystem ])).overrideAttrs (old: {
    # Preserve empty ASDF output-mapping fields in the existing binary wrapper.
    nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ pkgs.makeBinaryWrapper ];
    postFixup =
      (old.postFixup or "")
      + lib.optionalString defingerprinterSupported ''
        wrapProgram "$out/bin/sbcl" \
          --set AUTOLITH_DEFINGERPRINTER_LIBRARY "${defingerprinterNative.lib}/lib/libdefingerprinter${sharedLibrary}"
      ''
      + ''
        # Capture before withPackages' binary wrapper prefixes ASDF settings,
        # including direct worker and development-runtime invocations.
        mv "$out/bin/sbcl" "$out/bin/.autolith-sbcl"
        cat > "$out/bin/sbcl" <<EOF
        #!${pkgs.bash}/bin/bash
        source "${autolithSystem}/script/launcher-cli.sh"
        autolith_launcher_capture_asdf_environment
        # Keep private startup independent of the captured caller configuration.
        unset CL_SOURCE_REGISTRY ASDF_OUTPUT_TRANSLATIONS
        exec "$out/bin/.autolith-sbcl" "\$@"
        EOF
        chmod +x "$out/bin/sbcl"
      '';
  });

  # nixpkgs verifies the source archive for the selected compiler version.
  sbclSource =
    pkgs.runCommand "autolith-sbcl-${pkgs.sbcl.version}-source"
      {
        nativeBuildInputs = [
          pkgs.bzip2
          pkgs.coreutils
          pkgs.gnutar
          pkgs.gnugrep
        ];
      }
      ''
        mkdir -p "$out"
        tar -xjf ${pkgs.sbcl.src} --strip-components=1 -C "$out"
        grep -Fxq '"${pkgs.sbcl.version}"' "$out/version.lisp-expr"
        test -f "$out/src/code/list.lisp"
      '';

  # Resolve helpers from the Nix store, not the Lisp system's build directory.
  sandboxEnvironment = ''
    export CL_EXEC_SANDBOX_PROCESS_GROUP_HELPER="${sandboxHelper}/libexec/cl-exec-sandbox-process-group"
  ''
  + lib.optionalString pkgs.stdenv.hostPlatform.isLinux ''
    export CL_EXEC_SANDBOX_BWRAP="${pkgs.bubblewrap}/bin/bwrap"
    export CL_EXEC_SANDBOX_HELPER="${sandboxHelper}/libexec/cl-exec-sandbox-helper"
  '';

  # SBCL saved cores are intentionally transient here. Their bytes are not
  # reproducible, so the derivation publishes only a deterministic proof that
  # the complete Nix closure can build and probe both required images.
  imageValidation =
    pkgs.runCommand "autolith-image-validation-${pkgs.sbcl.version}"
      {
        nativeBuildInputs = [ pkgs.git ];
      }
      ''
        export HOME="$TMPDIR/home"
        export XDG_CONFIG_HOME="$TMPDIR/config"
        export XDG_DATA_HOME="$TMPDIR/data"
        export XDG_STATE_HOME="$TMPDIR/state"
        export AUTOLITH_SBCL="${runtime}/bin/sbcl"
        export AUTOLITH_SBCL_SOURCE_ROOT="${sbclSource}"
        export AUTOLITH_ASDF_CACHE="$TMPDIR/asdf-cache"
        export AUTOLITH_NIX_SOURCE_ROOT="${autolithSystem}/"
        export AUTOLITH_INSTALLATION_KIND=nix
        export COLORLISP_NATIVE_LIBRARY="${colorlispNativeLibrary}/lib/libcolorlisp-tree-sitter${sharedLibrary}"
        export AUTOLITH_FFF_LIBRARY="${fffLibrary}/lib/libfff_c${sharedLibrary}"
        ${sandboxEnvironment}
        export GIT_CONFIG_COUNT=1
        export GIT_CONFIG_KEY_0=safe.directory
        export GIT_CONFIG_VALUE_0="${autolithSystem}"
        export GIT_OPTIONAL_LOCKS=0

        image_root="$TMPDIR/images"
        mkdir -p "$HOME" "$AUTOLITH_ASDF_CACHE" \
          "$image_root/active" "$image_root/recovery"
        "$AUTOLITH_SBCL" --script "${autolithSystem}/script/build-recovery.lisp" \
          "$image_root/recovery/autolith-recovery.core"
        "$AUTOLITH_SBCL" --script "${autolithSystem}/script/build-active.lisp" \
          "$image_root/active/autolith-active.core"
        test -f "$image_root/recovery/autolith-recovery.core"
        test -f "$image_root/recovery/manifest.sexp"
        test -f "$image_root/active/autolith-active.core"
        test -f "$image_root/active/manifest.sexp"

        mkdir -p "$out"
        printf '%s\n' validated > "$out/image-validation"
      '';

  imageLockRunner = pkgs.writeText "autolith-image-lock.pl" ''
    use strict;
    use warnings;
    use Fcntl qw(LOCK_EX);

    my $lock_path = shift @ARGV;
    open my $lock, '>>', $lock_path or die "$lock_path: $!\n";
    flock($lock, LOCK_EX) or die "$lock_path: $!\n";
    my $status = system @ARGV;
    die "Could not start image materializer: $!\n" if $status == -1;
    exit(128 + ($status & 127)) if $status & 127;
    exit($status >> 8);
  '';

  imageMaterializer = pkgs.writeShellScript "autolith-materialize-nix-images" ''
    set -eu

    image_root=$1
    final=$2
    expected_identity='${imageIdentity}'
    stage=
    work=
    previous=

    image_set_valid()
    {
      directory=$1
      [ -d "$directory" ] &&
        [ ! -L "$directory" ] &&
        [ -f "$directory/identity" ] &&
        [ ! -L "$directory/identity" ] &&
        [ "$(cat "$directory/identity")" = "$expected_identity" ] &&
        [ -d "$directory/active" ] &&
        [ ! -L "$directory/active" ] &&
        [ -d "$directory/recovery" ] &&
        [ ! -L "$directory/recovery" ] &&
        [ -f "$directory/active/autolith-active.core" ] &&
        [ ! -L "$directory/active/autolith-active.core" ] &&
        [ -f "$directory/active/manifest.sexp" ] &&
        [ ! -L "$directory/active/manifest.sexp" ] &&
        [ -f "$directory/recovery/autolith-recovery.core" ] &&
        [ ! -L "$directory/recovery/autolith-recovery.core" ] &&
        [ -f "$directory/recovery/manifest.sexp" ] &&
        [ ! -L "$directory/recovery/manifest.sexp" ] &&
        [ -r "$directory/identity" ] &&
        [ -r "$directory/active/autolith-active.core" ] &&
        [ -r "$directory/active/manifest.sexp" ] &&
        [ -r "$directory/recovery/autolith-recovery.core" ] &&
        [ -r "$directory/recovery/manifest.sexp" ]
    }

    image_set_usable()
    {
      directory=$1
      image_set_valid "$directory" &&
        ${pkgs.gnugrep}/bin/grep -Eq \
          '^\(:SBCL-GENERATIONS-IMAGE-MANIFEST :VERSION 1([[:space:]]|$)' \
          "$directory/active/manifest.sexp" &&
        ${pkgs.gnugrep}/bin/grep -Eq \
          '^\(:RECOVERY-IMAGE :VERSION 2([[:space:]]|$)' \
          "$directory/recovery/manifest.sexp" &&
        "$AUTOLITH_SBCL" --noinform \
          --core "$directory/recovery/autolith-recovery.core" \
          --end-runtime-options "${autolithSystem}/" --probe \
          >/dev/null 2>&1 &&
        "$AUTOLITH_SBCL" --noinform \
          --core "$directory/active/autolith-active.core" \
          --end-runtime-options "${autolithSystem}/" \
          --autolith-internal-active-image-probe >/dev/null 2>&1
    }

    cleanup()
    {
      if [ -n "$stage" ] && [ -d "$stage" ]; then
        rm -rf "$stage"
      fi
      if [ -n "$work" ] && [ -d "$work" ]; then
        rm -rf "$work"
      fi
      if [ -n "$previous" ] && \
         { [ -e "$previous" ] || [ -L "$previous" ]; }; then
        rm -rf "$previous"
      fi
    }
    trap cleanup EXIT
    trap 'exit 1' HUP INT TERM

    if image_set_usable "$final"; then
      exit 0
    fi

    stage=$(mktemp -d "$image_root/.stage.XXXXXXXX")
    work=$(mktemp -d "$image_root/.work.XXXXXXXX")
    mkdir -p "$stage/active" "$stage/recovery" \
      "$work/home" "$work/config" "$work/data" "$work/state"
    export HOME="$work/home"
    export XDG_CONFIG_HOME="$work/config"
    export XDG_DATA_HOME="$work/data"
    export XDG_STATE_HOME="$work/state"

    "$AUTOLITH_SBCL" --script "${autolithSystem}/script/build-recovery.lisp" \
      "$stage/recovery/autolith-recovery.core"
    "$AUTOLITH_SBCL" --script "${autolithSystem}/script/build-active.lisp" \
      "$stage/active/autolith-active.core"
    "$AUTOLITH_SBCL" --script "${autolithSystem}/script/relocate-image-manifests.lisp" \
      "$stage" "$final"
    printf '%s\n' "$expected_identity" > "$stage/identity"
    image_set_valid "$stage"
    chmod u+w "$stage/active/autolith-active.core" \
      "$stage/active/manifest.sexp"

    if [ -e "$final" ] || [ -L "$final" ]; then
      previous=$(mktemp -d "$image_root/.invalid.XXXXXXXX")
      rmdir "$previous"
      mv "$final" "$previous"
    fi
    mv "$stage" "$final"
    stage=
    if [ -n "$previous" ]; then
      rm -rf "$previous"
      previous=
    fi
  '';

  # Packaged defaults apply if the corresponding variables are unset or empty.
  portableName = name: builtins.match "[A-Za-z0-9][A-Za-z0-9._-]*" name != null;
  launcherName = if commandName == null then "autolith" else commandName;
  packagedDefault =
    variable: value:
    lib.optionalString (value != null) ''
      if [ -z "''${${variable}:-}" ]; then
        export ${variable}=${lib.escapeShellArg (toString value)}
      fi
    '';
  packagedDefaults = lib.concatStrings [
    (packagedDefault "AUTOLITH_DIRECTORY_NAME" directoryName)
    (packagedDefault "AUTOLITH_PRODUCT_NAME" productName)
    (packagedDefault "AUTOLITH_COMMAND_NAME" commandName)
    (packagedDefault "AUTOLITH_SITE_CONFIG_ROOT" siteConfigRoot)
  ];

in
assert lib.assertMsg (qlotSourcesWithoutBuildMetadata == [ ])
  "qlfile.lock git sources without Nix build metadata in nix/package.nix: ${toString qlotSourcesWithoutBuildMetadata}";
assert lib.assertMsg
  (lib.subtractLists (builtins.attrNames qlotGitSources) qlotLibrariesWithBuildMetadata == [ ])
  "nix/package.nix lists build metadata for libraries no longer in qlfile.lock: ${toString (lib.subtractLists (builtins.attrNames qlotGitSources) qlotLibrariesWithBuildMetadata)}";
assert
  with pkgs.stdenv.hostPlatform; (isLinux && (isx86_64 || isAarch64)) || (isDarwin && isAarch64);
assert lib.versionAtLeast pkgs.sbcl.version minimumSbclVersion;
assert lib.assertMsg (directoryName == null || portableName directoryName)
  "directoryName ${toString directoryName} must match the ASCII pattern ^[A-Za-z0-9][A-Za-z0-9._-]*$.";
assert lib.assertMsg (
  commandName == null || portableName commandName
) "commandName ${toString commandName} must match the ASCII pattern ^[A-Za-z0-9][A-Za-z0-9._-]*$.";
pkgs.writeShellApplication {
  name = launcherName;
  runtimeInputs = [
    pkgs.bash
    pkgs.coreutils
    pkgs.git
    pkgs.gnugrep
    pkgs.perl
    runtime
  ]
  ++ lib.optionals pkgs.stdenv.hostPlatform.isLinux [
    pkgs.bubblewrap
    pkgs.procps
  ];
  text = ''
      ${packagedDefaults}
      # shellcheck source=/dev/null
      source "${autolithSystem}/script/launcher-cli.sh"
      autolith_launcher_capture_asdf_environment
      autolith_launcher_parse nix "$@"
      xdg_base_directory()
      {
        case ''${1:-} in
          /*) printf '%s\n' "$1" ;;
          *) printf '%s\n' "$2" ;;
        esac
      }

      home="''${HOME:-/home/user}"
      data_home=$(xdg_base_directory "''${XDG_DATA_HOME:-}" "$home/.local/share")
      cache_home=$(xdg_base_directory "''${XDG_CACHE_HOME:-}" "$home/.cache")
      directory_name=$(autolith_directory_name) || exit 1
      # ASDF reads this variable before project initialization can validate it.
      export XDG_CACHE_HOME="$cache_home"
    export AUTOLITH_SBCL="${runtime}/bin/sbcl"
    export AUTOLITH_SBCL_SOURCE_ROOT="${sbclSource}"
    export COLORLISP_NATIVE_LIBRARY="${colorlispNativeLibrary}/lib/libcolorlisp-tree-sitter${sharedLibrary}"
    export AUTOLITH_FFF_LIBRARY="${fffLibrary}/lib/libfff_c${sharedLibrary}"
    ${sandboxEnvironment}

    # The packaged source repository is root-owned in /nix/store. Permit Git
    # provenance reads without weakening safe.directory globally.
    export GIT_CONFIG_COUNT=2
    export GIT_CONFIG_KEY_0=safe.directory
    export GIT_CONFIG_VALUE_0="${autolithSystem}"
    export GIT_CONFIG_KEY_1=safe.directory
    export GIT_CONFIG_VALUE_1="${autolithSystem}/.git"
    export GIT_OPTIONAL_LOCKS=0

    # Keep durable Nix images under data and regenerable ASDF output under cache.
    nix_root="$data_home/$directory_name/nix"
    identity_name="${builtins.baseNameOf (toString imageIdentity)}"
    image_root="$nix_root/images"
    image_directory="$image_root/$identity_name"
    asdf_cache="$cache_home/$directory_name/nix/asdf-cache/$identity_name"
    (umask 077; mkdir -p "$data_home/$directory_name" "$cache_home/$directory_name" \
      "$image_root" "$asdf_cache")
    export AUTOLITH_ASDF_CACHE="$asdf_cache"
    export AUTOLITH_NIX_SOURCE_ROOT="${autolithSystem}/"
    export AUTOLITH_INSTALLATION_KIND=nix

    # Nix validates image construction at package-build time, but SBCL cores
    # are machine-local mutable state rather than reproducible store outputs.
    # Serialize first-use construction and publish each package identity as one
    # complete directory so upgrades never expose or reuse a partial image pair.
    test -f "${imageValidation}/image-validation"
    image_output_fd=1
    # Assigned by autolith_launcher_parse in the sourced launcher.
    # shellcheck disable=SC2154
    if [ "$acp_requested" = true ]; then
      image_output_fd=2
    fi
    ${pkgs.perl}/bin/perl "${imageLockRunner}" \
      "$image_root/.materialize.lock" \
      "${imageMaterializer}" "$image_root" "$image_directory" >&"$image_output_fd"

    export AUTOLITH_ACTIVE_CORE="$image_directory/active/autolith-active.core"
    export AUTOLITH_RECOVERY_CORE="$image_directory/recovery/autolith-recovery.core"

    exec ${pkgs.bash}/bin/bash "${autolithSystem}/bin/autolith" "$@"
  '';

  meta = {
    description = "A live, self-modifying Common Lisp agent";
    homepage = "https://github.com/lambda-symbolics/autolith";
    license = lib.licenses.mit;
    mainProgram = launcherName;
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
      "aarch64-darwin"
    ];
  };

  passthru = {
    inherit qlotGitSources;
    inherit
      defingerprinter
      defingerprinterNative
      defingerprinterSupported
      defingerprinterChecks
      ;
    tests.defingerprinter = defingerprinterChecks;
    inherit
      autolithSystem
      clColorist
      clExecSandbox
      clifff
      clinedi
      clJobpond
      colorlisp
      colorlispNativeLibrary
      fffLibrary
      idsmall
      imageIdentity
      imageValidation
      runtime
      sandboxHelper
      sbclGenerations
      sbclSource
      mcparen
      testRuntime
      sbclWorkers
      sexpConfig
      sexpStore
      ;
  };
}
