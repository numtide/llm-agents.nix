{
  lib,
  makeSetupHook,
  writeText,
}:

let
  header = writeText "darwin-openpty-shim.h" ''
    #ifndef DARWIN_OPENPTY_SHIM_H
    #define DARWIN_OPENPTY_SHIM_H

    /*
     * https://github.com/NixOS/nixpkgs/issues/457238
     *
     * macOS node-gyp builds sometimes see src/util.h from Node.js instead of
     * the SDK's util.h. That header does not declare openpty(3)/forkpty(3),
     * which causes node-pty (and other consumers) to fail to build. Including
     * this shim restores the missing declarations without depending on the
     * system header lookup.
     */
    #include <sys/types.h>

    struct termios;
    struct winsize;

    #ifdef __cplusplus
    extern "C" {
    #endif

    int openpty(int *, int *, char *, struct termios *, struct winsize *);
    pid_t forkpty(int *, char *, struct termios *, struct winsize *);

    #ifdef __cplusplus
    }
    #endif

    #endif /* DARWIN_OPENPTY_SHIM_H */
  '';

  hookScript = writeText "darwin-openpty-hook.sh" ''
    # shellcheck shell=bash
    if [ -z "''${darwinOpenptyHookApplied-}" ]; then
      export NIX_CFLAGS_COMPILE="''${NIX_CFLAGS_COMPILE-} -include ${header}"
      darwinOpenptyHookApplied=1
    fi
  '';
in
makeSetupHook {
  name = "darwin-openpty-hook";
  meta = {
    description = "Setup hook that injects openpty/forkpty prototypes on Darwin";
    platforms = lib.platforms.darwin;
  };
  passthru = {
    hideFromDocs = true;
  };
} hookScript
