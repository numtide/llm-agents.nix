# shellcheck shell=bash
# Fails the build unless every Mach-O in the outputs and in $codesignSources
# carries a Developer ID signature from team $codesignTeamId whose certificate
# chains to Apple's root CA. Runs on any host: rcodesign and openssl do not
# need macOS.

codesignIsMachO() {
  local magic
  magic=$(head -c 4 "$1" | od -An -tx1 | tr -d ' \n')
  case $magic in
  cffaedfe | feedfacf | cafebabe | bebafeca) return 0 ;;
  *) return 1 ;;
  esac
}

# $@ selects the slice of a universal binary (--universal-index N).
codesignCheckSlice() {
  local file=$1
  shift
  local dir subject
  dir=$(mktemp -d)
  rcodesign extract "$@" cms-pem "$file" >"$dir/cms.pem"
  rcodesign extract "$@" code-directory-raw "$file" >"$dir/cd.bin"
  # apple marks its developer id extension critical; openssl rejects unknown
  # critical extensions unless told to ignore them
  openssl cms -verify -binary -inform PEM -in "$dir/cms.pem" -content "$dir/cd.bin" \
    -CAfile @appleRootCa@ -purpose any -ignore_critical -out /dev/null -signer "$dir/signer.pem"
  subject=$(openssl x509 -in "$dir/signer.pem" -noout -subject -nameopt RFC2253)
  rm -rf "$dir"
  if [[ $subject != *"CN=Developer ID Application:"* || $subject != *"OU=$codesignTeamId,"* ]]; then
    echo "codesignCheckHook: $file is signed by '$subject', expected team $codesignTeamId" >&2
    return 1
  fi
}

codesignCheckFile() {
  local file=$1 magic nfat i
  echo "codesignCheckHook: checking $file"
  # verify walks every slice of a universal binary by itself
  rcodesign verify "$file"
  magic=$(head -c 4 "$file" | od -An -tx1 | tr -d ' \n')
  case $magic in
  cafebabe | bebafeca)
    nfat=$((16#$(head -c 8 "$file" | tail -c 4 | od -An -tx1 | tr -d ' \n')))
    for ((i = 0; i < nfat; i++)); do
      codesignCheckSlice "$file" --universal-index "$i"
    done
    ;;
  *) codesignCheckSlice "$file" ;;
  esac
}

codesignCheckTree() {
  local file
  while IFS= read -r -d '' file; do
    if codesignIsMachO "$file"; then
      codesignCheckFile "$file"
      codesignChecked=$((codesignChecked + 1))
    fi
  done < <(find "$1" -type f -print0)
}

codesignCheck() {
  if [[ -z ${codesignTeamId-} ]]; then
    echo "codesignCheckHook: codesignTeamId is not set" >&2
    return 1
  fi
  codesignChecked=0
  local output src dir
  for output in $(getAllOutputNames); do
    codesignCheckTree "${!output}"
  done
  for src in ${codesignSources-}; do
    if codesignIsMachO "$src"; then
      codesignCheckFile "$src"
      codesignChecked=$((codesignChecked + 1))
    else
      dir=$(mktemp -d)
      pushd "$dir" >/dev/null || return 1
      unpackFile "$src"
      popd >/dev/null || return 1
      codesignCheckTree "$dir"
      rm -rf "$dir"
    fi
  done
  if ((codesignChecked == 0)); then
    echo "codesignCheckHook: no Mach-O binaries found to verify" >&2
    return 1
  fi
  echo "codesignCheckHook: verified $codesignChecked Mach-O binaries for team $codesignTeamId"
}

preInstallCheckHooks+=(codesignCheck)
