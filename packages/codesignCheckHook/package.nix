{
  lib,
  makeSetupHook,
  openssl,
  rcodesign,
}:

makeSetupHook {
  name = "codesign-check-hook";
  propagatedBuildInputs = [
    openssl
    rcodesign
  ];
  substitutions = {
    # https://www.apple.com/appleca/AppleIncRootCertificate.cer
    # sha256 B0B1730ECBC7FF4505142C49F1295E6EDA6BCAED7E2C68C5BE91B5A11001F024
    appleRootCa = ./apple-root-ca.pem;
  };
  passthru.hideFromDocs = true;
  passthru.skipUpdate = true;
  meta = {
    description = "Setup hook that verifies Developer ID code signatures on Mach-O binaries";
    license = lib.licenses.mit;
    platforms = lib.platforms.all;
  };
} ./codesign-check.sh
