{
  lib,
  python3,
  fetchFromGitHub,
  fetchPypi,
  makeWrapper,
  ffmpeg,
  xdotool,
  wtype,
  ydotool,
}:

let
  python = python3.override {
    self = python;
    packageOverrides = _final: prev: {
      # Fails in the sandbox on torchcodec 0.16.0. Drop this override once
      # nixpkgs includes NixOS/nixpkgs@6a3590bb67fd, which skips it too
      # (tracked in #10453).
      torchcodec = prev.torchcodec.overridePythonAttrs (old: {
        disabledTests = (old.disabledTests or [ ]) ++ [ "test_audio_against_cli" ];
      });
    };
  };

  # Not yet in nixpkgs. Packaged inline; all transitive deps are available.
  faster-whisper = python.pkgs.buildPythonPackage rec {
    pname = "faster-whisper";
    version = "1.2.1";
    pyproject = true;

    src = fetchFromGitHub {
      owner = "SYSTRAN";
      repo = "faster-whisper";
      tag = "v${version}";
      hash = "sha256-pWVYxC1h0kIhhBxAt9oT2USuvoarlcwwYmaLUJlZZwY=";
    };

    build-system = with python.pkgs; [ setuptools ];

    dependencies = with python.pkgs; [
      av
      ctranslate2
      huggingface-hub
      onnxruntime
      tokenizers
      tqdm
    ];

    pythonImportsCheck = [ "faster_whisper" ];
    # Test suite downloads models from the Hugging Face Hub.
    doCheck = false;

    meta = {
      description = "Faster Whisper transcription with CTranslate2";
      homepage = "https://github.com/SYSTRAN/faster-whisper";
      license = lib.licenses.mit;
      sourceProvenance = with lib.sourceTypes; [ fromSource ];
      platforms = lib.platforms.all;
    };
  };

  # Not yet in nixpkgs. VoxTerm only reads the bundled ONNX model via
  # onnxruntime (see audio/vad.py), but we keep torch in the deps to match
  # upstream metadata.
  silero-vad = python.pkgs.buildPythonPackage rec {
    pname = "silero-vad";
    version = "6.2.1";
    pyproject = true;

    src = fetchPypi {
      pname = "silero_vad";
      inherit version;
      hash = "sha256-sjBisOOfrRexJm/CPB57QpAhnb6CzghRCInjL2gfSzs=";
    };

    build-system = with python.pkgs; [ hatchling ];

    dependencies = with python.pkgs; [
      onnxruntime
      packaging
      torch
      torchaudio
    ];

    pythonImportsCheck = [ "silero_vad" ];

    meta = {
      description = "Pre-trained enterprise-grade Voice Activity Detector";
      homepage = "https://github.com/snakers4/silero-vad";
      license = lib.licenses.mit;
      sourceProvenance = with lib.sourceTypes; [ fromSource ];
      platforms = lib.platforms.all;
    };
  };
in
python.pkgs.buildPythonApplication rec {
  pname = "voxterm";
  version = "0.3.0";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "dmarzzz";
    repo = "VoxTerm";
    tag = "v${version}";
    hash = "sha256-yOmqc0EnK4UkIWfYZlae5yGnDH/xlj6nwPOR0oC/SCU=";
  };

  build-system = with python.pkgs; [ hatchling ];

  nativeBuildInputs = [ makeWrapper ];

  dependencies = with python.pkgs; [
    cryptography
    numpy
    onnxruntime
    scipy
    silero-vad
    sounddevice
    textual
    zeroconf
    faster-whisper
    pillow
    pystray
    xlib
  ];

  # qwen-asr is an optional transcription backend (probed at runtime via
  # importlib.util.find_spec; VoxTerm falls back to faster-whisper when it is
  # absent). It pulls exact-pinned, unpackaged deps (nagisa, soynlp,
  # qwen-omni-utils), so we drop it from the dependency closure.
  pythonRemoveDeps = [ "qwen-asr" ];

  # onnxruntime is capped <1.24 upstream to avoid a heap leak; nixpkgs ships a
  # newer release. torch is pulled in transitively via silero-vad.
  pythonRelaxDeps = [
    "onnxruntime"
    "torch"
  ];

  # tui.app sets up a faulthandler crash dir under $HOME on import, so the
  # import check needs a writable HOME.
  preBuild = ''
    export HOME=$(mktemp -d)
  '';

  pythonImportsCheck = [ "tui.app" ];

  # Dictation mode shells out to ffmpeg and keyboard-injection tools.
  postFixup = ''
    wrapProgram $out/bin/voxterm \
      --prefix PATH : ${
        lib.makeBinPath [
          ffmpeg
          xdotool
          wtype
          ydotool
        ]
      }
  '';

  passthru.category = "Voice & Transcription";

  meta = {
    description = "Local real-time voice transcription TUI with speaker diarization";
    homepage = "https://github.com/dmarzzz/VoxTerm";
    changelog = "https://github.com/dmarzzz/VoxTerm/releases/tag/v${version}";
    license = lib.licenses.mit;
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
    maintainers = with lib.maintainers; [ zimbatm ];
    # macOS support requires unpackaged MLX backends; Linux-only for now.
    platforms = lib.platforms.linux;
    mainProgram = "voxterm";
  };
}
