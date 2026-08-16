{
  pkgs,
  callPackage,
  # Make claude-code overridable
  claude-code,
  # Keep this so package.nix can be copied into llm-agents.nix
  sourceDir ? "${callPackage ./source.nix { }}/src",
}:
let
  inherit (pkgs.stdenv) isLinux isDarwin;

  # Bundle all the tools Claude needs into a single environment
  claudeTools = pkgs.buildEnv {
    name = "claude-tools";
    paths = with pkgs; [
      # Essential tools Claude commonly uses
      git
      ripgrep
      fd
      coreutils
      gnugrep
      gnused
      gawk
      findutils
      which
      tree
      curl
      wget
      jq
      less
      # Shells
      zsh
      # Nix is essential for nix run
      nix
    ];
  };

  # Platform-specific sandbox tools
  sandboxTools = if isLinux then [ pkgs.bubblewrap ] else [ ];

  # Seatbelt profile for macOS (only installed on darwin)
  seatbeltProfile = "${sourceDir}/seatbelt.sbpl";

in
pkgs.runCommand "claudebox"
  {
    buildInputs = [ pkgs.makeWrapper ];
    passthru.category = "Sandboxing & Isolation";
    meta = with pkgs.lib; {
      mainProgram = "claudebox";
      description = "Sandboxed environment for Claude Code";
      homepage = "https://github.com/numtide/claudebox";
      changelog = "https://github.com/numtide/claudebox/releases";
      sourceProvenance = with sourceTypes; [ fromSource ];
      platforms = platforms.linux ++ platforms.darwin;
    };
  }
  ''
    mkdir -p $out/bin $out/share/claudebox $out/libexec/claudebox

    # Install claudebox launcher script
    cp ${sourceDir}/claudebox.js $out/libexec/claudebox/claudebox.js

    # Install seatbelt profile for macOS
    cp ${seatbeltProfile} $out/share/claudebox/seatbelt.sbpl

    # Create claudebox executable with platform-specific configuration
    makeWrapper ${pkgs.bun}/bin/bun $out/bin/claudebox \
      --add-flags $out/libexec/claudebox/claudebox.js \
      --prefix PATH : ${
        pkgs.lib.makeBinPath (
          [
            pkgs.bashInteractive
            claudeTools
          ]
          ++ sandboxTools
        )
      } \
      ${if isDarwin then "--set CLAUDEBOX_SEATBELT_PROFILE $out/share/claudebox/seatbelt.sbpl" else ""}

    # Create claude wrapper. claude-code is now a corepkgs build: its public
    # entrypoint is bin/claude (a wrapper that invokes the pinned loader and
    # sets DISABLE_AUTOUPDATER itself), not the nixpkgs makeWrapper
    # .claude-wrapped. Wrap that.
    makeWrapper ${claude-code}/bin/claude $out/libexec/claudebox/claude \
      --set DISABLE_AUTOUPDATER 1 \
      --inherit-argv0
  ''
