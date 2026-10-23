{
  lib,
  runCommand,
  makeShellWrapper,
  runtimeShell,
  fd,
  ripgrep,
  installDarwin,
  resetDarwinAppDirs,
  toolPath,
}:

runCommand "kimi-code-desktop-darwin-launcher-test" { nativeBuildInputs = [ makeShellWrapper ]; } ''
  testOut=$out
  # Spaces also exercise quoting in the launcher and its target path.
  out="$TMPDIR/packaged app"
  original='Kimi Code.app/Contents'
  mkdir -p "$original"/{MacOS,Resources,Frameworks,_CodeSignature}
  printf 'hidden bundle metadata\n' > 'Kimi Code.app/.bundle-metadata'
  printf 'upstream metadata\n' > "$original/Info.plist"
  printf 'APPL????' > "$original/PkgInfo"
  printf 'upstream icon\n' > "$original/Resources/icon.icns"
  printf 'upstream signature\n' > "$original/_CodeSignature/CodeResources"
  cat > "$original/MacOS/Kimi Code" <<'EOF'
  #!${runtimeShell}
  set -eu
  test "$(command -v fd)" = ${lib.escapeShellArg (lib.getExe fd)}
  test "$(command -v rg)" = ${lib.escapeShellArg (lib.getExe ripgrep)}
  fd --version >/dev/null
  rg --version >/dev/null
  printf '%s\0' "$PATH" "$@"
  exit "''${KIMI_TEST_EXIT:-0}"
  EOF
  chmod +x "$original/MacOS/Kimi Code"

  ${installDarwin}
  app="$out/libexec/kimi-code-desktop/Kimi Code.app"
  contents="$out/Applications/Kimi Code.app/Contents"
  appInode=$(stat -c %i "$app")
  launcherInode=$(stat -c %i "$out/Applications/Kimi Code.app")
  # Directory recreation must retain the complete bundle, including hidden
  # entries, and leave both launchers usable.
  ${resetDarwinAppDirs}
  app="$out/libexec/kimi-code-desktop/Kimi Code.app"
  test "$(stat -c %i "$app")" != "$appInode"
  test "$(stat -c %i "$out/Applications/Kimi Code.app")" != "$launcherInode"
  test ! -e "$app.tmp"
  test ! -e "$out/Applications/Kimi Code.app.tmp"
  diff -r 'Kimi Code.app' "$app"
  for resource in Info.plist PkgInfo Frameworks Resources; do
    test "$(readlink "$contents/$resource")" = "$app/Contents/$resource"
  done
  test ! -e "$contents/_CodeSignature"
  test "$out/bin/kimi-code-desktop" -ef "$contents/MacOS/Kimi Code"

  for entry in "$contents/MacOS/Kimi Code" "$out/bin/kimi-code-desktop"; do
    # Finder's minimal PATH, an existing user PATH, and an empty PATH.
    for inheritedPath in /usr/bin:/bin '/custom tools/bin:/usr/bin:/bin' ""; do
      printf '%s\0' ${lib.escapeShellArg toolPath}"''${inheritedPath:+:$inheritedPath}" \
        'project with spaces' 'kimi-code://callback?code=a&state=b' > expected
      env -i PATH="$inheritedPath" "$entry" \
        'project with spaces' 'kimi-code://callback?code=a&state=b' > actual
      cmp expected actual
    done

    if env -i PATH=/usr/bin:/bin KIMI_TEST_EXIT=23 "$entry" > /dev/null; then
      echo 'Launcher lost the application exit status' >&2
      exit 1
    else
      test "$?" -eq 23
    fi
  done

  mkdir "$testOut"
''
