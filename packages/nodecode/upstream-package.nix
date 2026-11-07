{ pkgs, src }:

let
  lib = pkgs.lib;
  platforms = pkgs.lib.platforms;

  # Nodecode's SBCL system dependencies (from src/nodecode.asd)
  clDeps = with pkgs.sbclPackages; [
    bordeaux-threads
    shasht
    cl-ppcre
    dexador
    flexi-streams
    alexandria
    sqlite
    cl_plus_ssl
    cl-base64
    clack
    clack-handler-hunchentoot
    websocket-driver
    ironclad
  ];

  # Build nodecode system using ASDF
  nodecodeSystem = pkgs.sbcl.buildASDFSystem {
    pname = "nodecode";
    version = "0.0.1";
    inherit src;
    systems = [ "nodecode" ];
    lispLibs = clDeps;
  };

  # Build nodecode/bin for the standalone executable
  nodecodeBinSystem = pkgs.sbcl.buildASDFSystem {
    pname = "nodecode-bin";
    version = "0.0.1";
    inherit src;
    systems = [ "nodecode/bin" ];
    lispLibs = clDeps;
  };

  runtime = pkgs.sbcl.withPackages (_: [ nodecodeSystem ]);

in
pkgs.writeShellApplication {
  name = "nodecode";
  runtimeInputs = [
    pkgs.bash
    pkgs.coreutils
    pkgs.git
    runtime
  ];
  text = ''
    export SBCL_HOME="${runtime}/lib/sbcl"
    exec "${runtime}/bin/sbcl" \
      --noinform \
      --non-interactive \
      --eval "(require :asdf)" \
      --eval "(push \"${nodecodeSystem}/\" asdf:*central-registry*)" \
      --eval "(asdf:load-system :nodecode/bin)" \
      --eval "(nodecode.evolved::main)" \
      "$@"
  '';

  meta = {
    description = "A self-modifying agent organism in SBCL";
    homepage = "https://github.com/nodecode-ai/nodecode";
    license = lib.licenses.mit;
    mainProgram = "nodecode";
    platforms = platforms.linux;
  };
}