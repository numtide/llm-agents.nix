# Per-system table (pure - no storePath, usable from a flake). One row per system.
# Arch-specific pins (glibc, formatelf) come from a pins provider, not here.
# Toolchain versions stay in the toolchain files (shared across arches); only the
# per-arch platform token + hash live here.
_scope: {
  x86_64-linux = {
    loader = "ld-linux-x86-64.so.2";
    busybox = {
      url = "https://busybox.net/downloads/binaries/1.35.0-x86_64-linux-musl/busybox";
      hash = "sha256-mVOoYPn3r9NYiZjQf5AF2p7hXy1Q4kN5RSscc/PGpiY=";
    };
    nu = {
      url = "https://github.com/nushell/nushell/releases/download/0.114.1/nu-0.114.1-x86_64-unknown-linux-musl.tar.gz";
      hash = "sha256-zjocWgfHhAmLVnUiShZec6RfD3IKg5J5HXw6W0cgJV4=";
      dir = "nu-0.114.1-x86_64-unknown-linux-musl";
    };
    bun.platform = "linux-x64";
    node.platform = "linux-x64";
    zig.platform = "x86_64-linux";
    go.platform = "linux-amd64";
    rust = {
      gnu = "x86_64-unknown-linux-gnu";
      musl = "x86_64-unknown-linux-musl";
    };
  };

  # Darwin: Mach-O, not ELF - no loader, no busybox, no glibc/formatelf pins.
  # Prebuilt CLIs link system /usr/lib/libSystem via dyld, so they just run. The
  # build uses the system toolchain in the sandbox (/usr/bin/tar, /bin/chmod).
  # Only nushell is fetched.
  aarch64-darwin = {
    nu = {
      url = "https://github.com/nushell/nushell/releases/download/0.114.1/nu-0.114.1-aarch64-apple-darwin.tar.gz";
      hash = "sha256-ywrJuXuYXNIXqVL0RDihTS3yqVUE2b2LwB7HPhNRsXk=";
      dir = "nu-0.114.1-aarch64-apple-darwin";
    };
    # darwin: no gnu/musl split; the single apple-darwin triple is `rust.gnu`.
    zig.platform = "aarch64-macos";
    rust.gnu = "aarch64-apple-darwin";
  };

  x86_64-darwin = {
    nu = {
      url = "https://github.com/nushell/nushell/releases/download/0.114.1/nu-0.114.1-x86_64-apple-darwin.tar.gz";
      hash = "sha256-RlmnhUW39qMD5mH+O9J2p2XGTM3mcRLTIEW+X+B18gY=";
      dir = "nu-0.114.1-x86_64-apple-darwin";
    };
  };

  aarch64-linux = {
    loader = "ld-linux-aarch64.so.1";
    busybox = {
      # busybox.net ships no 64-bit aarch64 static build; use a pinned static one.
      url = "https://raw.githubusercontent.com/shutingrz/busybox-static-binaries-fat/1c31914c2398b04764b0e532299f8c842b4c6890/busybox-aarch64-linux-gnu";
      hash = "sha256-0lKJdLzmzYExtBDfj6o8vIMnqUsCgw/BbDxoZEJPlXQ=";
    };
    nu = {
      url = "https://github.com/nushell/nushell/releases/download/0.114.1/nu-0.114.1-aarch64-unknown-linux-musl.tar.gz";
      hash = "sha256-T56IDnu/juWPOGDvSfRT6yYolltvLIgPsD1HdfKQtTY=";
      dir = "nu-0.114.1-aarch64-unknown-linux-musl";
    };
    bun.platform = "linux-aarch64";
    node.platform = "linux-arm64";
    zig.platform = "aarch64-linux";
    go.platform = "linux-arm64";
    rust = {
      gnu = "aarch64-unknown-linux-gnu";
      musl = "aarch64-unknown-linux-musl";
    };
  };
}
