{
  lib,
  stdenv,
  fetchFromGitHub,
  cmake,
  # Release-matched revisions and hashes from hashes.json.
  pins,
}:
let
  simpleRepo = {
    owner = "wangfenjin";
    repo = "simple";
  };
  cppjiebaRepo = {
    owner = "yanyiwu";
    repo = "cppjieba";
  };
  gitUrl = r: "https://github.com/${r.owner}/${r.repo}.git";

  cppjieba = fetchFromGitHub (cppjiebaRepo // { inherit (pins.cppjieba) rev hash; });
in
stdenv.mkDerivation {
  pname = "agentsview-cjk";
  version = "0-unstable-${lib.substring 0 7 pins.simple.rev}";

  src = fetchFromGitHub (simpleRepo // { inherit (pins.simple) rev hash; });

  nativeBuildInputs = [ cmake ];

  # Replace CMake's download with agentsview's pin, regardless of simple's GIT_TAG.
  postPatch = ''
    cmakeFile=src/CMakeLists.txt
    repositoryLine=$(grep -E '^[[:space:]]*GIT_REPOSITORY[[:space:]]+[^[:space:]]+[[:space:]]*$' "$cmakeFile")
    tagLine=$(grep -E '^[[:space:]]*GIT_TAG[[:space:]]+[^[:space:]]+[[:space:]]*$' "$cmakeFile")
    if [ "$(printf '%s\n' "$repositoryLine" | wc -l)" -ne 1 ] \
      || [ "$(printf '%s\n' "$tagLine" | wc -l)" -ne 1 ] \
      || [ "$(grep -cE '^[[:space:]]*GIT_' "$cmakeFile")" -ne 2 ]; then
      echo "simple CMakeLists.txt must contain exactly one GIT_REPOSITORY and one GIT_TAG" >&2
      exit 1
    fi

    # Match the URL literally; punctuation must not act as regex syntax.
    read -r _ repository <<< "$repositoryLine"
    if [ "$repository" != ${lib.escapeShellArg (gitUrl cppjiebaRepo)} ]; then
      echo "unexpected cppjieba repository: $repository" >&2
      exit 1
    fi
    substituteInPlace "$cmakeFile" \
      --replace-fail "$repositoryLine" "SOURCE_DIR ${cppjieba}" \
      --replace-fail "$tagLine" 'DOWNLOAD_COMMAND ""'
  '';

  cmakeFlags = [
    "-DBUILD_SQLITE3=OFF"
    "-DBUILD_TEST_EXAMPLE=OFF"
    "-DSIMPLE_WITH_JIEBA=ON"
  ];

  installPhase = ''
    runHook preInstall
    target=$out/lib/agentsview/simple
    install -Dm755 src/libsimple${stdenv.hostPlatform.extensions.sharedLibrary} -t "$target"
    for name in hmm_model.utf8 idf.utf8 jieba.dict.utf8 stop_words.utf8 user.dict.utf8; do
      install -Dm644 ${cppjieba}/dict/"$name" -t "$target/dict"
    done
    install -Dm644 ../LICENSE "$target/licenses/simple-LICENSE"
    install -Dm644 ${cppjieba}/LICENSE "$target/licenses/cppjieba-LICENSE"
    printf '%s\n' 'simple ${pins.simple.rev}' 'cppjieba ${pins.cppjieba.rev}' > "$target/VERSIONS"
    runHook postInstall
  '';

  passthru = {
    inherit pins;
    simpleGitUrl = gitUrl simpleRepo;
  };

  meta = {
    description = "Optional CJK SQLite tokenizer and dictionaries for agentsview";
    homepage = "https://github.com/wangfenjin/simple";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux ++ lib.platforms.darwin;
  };
}
