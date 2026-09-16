{
  pkgs,
  flake,
  wrapBuddy,
  versionCheckHomeHook,
  codesignCheckHook,
}:

let
  hashes = builtins.fromJSON (builtins.readFile ./hashes.json);
  version = hashes.version;

  darwinSrc = pkgs.fetchurl {
    url = "https://github.com/editor-code-assistant/eca/releases/download/${version}/eca-native-macos-aarch64.zip";
    hash = hashes."aarch64-darwin";
  };

  # Function to create native binary derivation for each platform
  mkNativeBinary =
    {
      system,
      url,
      hash,
      wrapBuddy,
      versionCheckHomeHook,
    }:
    pkgs.stdenv.mkDerivation {
      pname = "eca";
      inherit version;

      src = pkgs.fetchurl {
        inherit url hash;
      };

      nativeBuildInputs = [
        pkgs.unzip
      ]
      ++ pkgs.lib.optionals pkgs.stdenv.hostPlatform.isLinux [
        wrapBuddy
      ];

      buildInputs = pkgs.lib.optionals pkgs.stdenv.hostPlatform.isLinux [
        pkgs.zlib
      ];

      doInstallCheck = true;
      nativeInstallCheckInputs = [
        pkgs.versionCheckHook
        versionCheckHomeHook
        codesignCheckHook
      ];
      codesignTeamId = "762737A9Q2";
      codesignSources = [ darwinSrc ];

      unpackPhase = ''
        runHook preUnpack
        unzip $src
        runHook postUnpack
      '';

      dontBuild = true;
      # stripping invalidates the darwin code signature
      dontStrip = pkgs.stdenv.hostPlatform.isDarwin;

      installPhase = ''
        runHook preInstall
        mkdir -p $out/bin
        cp eca $out/bin/eca
        chmod +x $out/bin/eca
        runHook postInstall
      '';

      passthru.category = "AI Coding Agents";

      meta = with pkgs.lib; {
        description = "Editor Code Assistant (ECA) - AI pair programming capabilities agnostic of editor";
        homepage = "https://github.com/editor-code-assistant/eca";
        changelog = "https://github.com/editor-code-assistant/eca/releases/tag/${version}";
        license = licenses.asl20;
        sourceProvenance = with sourceTypes; [ binaryNativeCode ];
        maintainers = with flake.lib.maintainers; [ zrubing ];
        mainProgram = "eca";
        platforms = [ system ];
      };
    };

in
# Use native binary for all supported platforms
if pkgs.stdenv.hostPlatform.system == "x86_64-linux" then
  mkNativeBinary {
    inherit wrapBuddy versionCheckHomeHook;
    system = "x86_64-linux";
    url = "https://github.com/editor-code-assistant/eca/releases/download/${version}/eca-native-linux-amd64.zip";
    hash = hashes."x86_64-linux";
  }
else if pkgs.stdenv.hostPlatform.system == "aarch64-linux" then
  mkNativeBinary {
    inherit wrapBuddy versionCheckHomeHook;
    system = "aarch64-linux";
    url = "https://github.com/editor-code-assistant/eca/releases/download/${version}/eca-native-linux-aarch64.zip";
    hash = hashes."aarch64-linux";
  }
else if pkgs.stdenv.hostPlatform.system == "aarch64-darwin" then
  mkNativeBinary {
    inherit wrapBuddy versionCheckHomeHook;
    system = "aarch64-darwin";
    url = darwinSrc.url;
    hash = hashes."aarch64-darwin";
  }
else
  # Fallback to JAR version for unsupported platforms
  pkgs.stdenv.mkDerivation rec {
    pname = "eca";
    inherit version;

    src = pkgs.fetchurl {
      url = "https://github.com/editor-code-assistant/eca/releases/download/${version}/eca.jar";
      hash = hashes.jar;
    };

    nativeBuildInputs = [
      pkgs.makeWrapper
    ];

    buildInputs = [
      pkgs.jre
    ];

    doInstallCheck = true;
    nativeInstallCheckInputs = [
      pkgs.versionCheckHook
      versionCheckHomeHook
    ];

    dontUnpack = true;
    dontBuild = true;

    installPhase = ''
      runHook preInstall
      mkdir -p $out/bin
      mkdir -p $out/lib
      cp $src $out/lib/eca.jar

      cat > $out/bin/eca << EOF
      #!${pkgs.stdenv.shell}
      export JAVA_HOME="${pkgs.jre}"
      export PATH="${pkgs.jre}/bin:\$PATH"
      exec "${pkgs.jre}/bin/java" -jar "$out/lib/eca.jar" "\$@"
      EOF

      chmod +x $out/bin/eca
      runHook postInstall
    '';

    passthru.category = "AI Coding Agents";

    meta = with pkgs.lib; {
      description = "Editor Code Assistant (ECA) - AI pair programming capabilities agnostic of editor";
      homepage = "https://github.com/editor-code-assistant/eca";
      changelog = "https://github.com/editor-code-assistant/eca/releases/tag/${version}";
      license = licenses.asl20;
      sourceProvenance = with sourceTypes; [ binaryBytecode ];
      maintainers = with flake.lib.maintainers; [ zrubing ];
      mainProgram = "eca";
    };
  }
