# shellcheck shell=bash
# Setup hook that provides a writable HOME for versionCheckHook
# Use this when the binary being version-checked requires HOME to be set

versionCheckHome() {
  if [[ ! -v HOME ]] || [[ ! -w $HOME ]]; then
    HOME="$NIX_BUILD_TOP/.version-check-home"
    mkdir -p "$HOME"
    export HOME
  fi
  # Add HOME to the list of env vars passed through to the version check command
  # Skip if already keeping all env vars
  if [[ ${versionCheckKeepEnvironment:-} != "*" ]]; then
    versionCheckKeepEnvironment="${versionCheckKeepEnvironment-} HOME"
  fi
}

preVersionCheckHooks+=(versionCheckHome)
