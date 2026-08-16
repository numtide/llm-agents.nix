# Pin provider: pure, nixpkgs-free, and cache-free at eval. References exact store
# paths via `builtins.appendContext` instead of `builtins.fetchClosure` - no
# narinfo fetch at eval, so eval is instant + offline; paths substitute from the
# configured caches at realize time. Substitute-only, never built (a cache miss
# falls back to pins/pkgs.nix). Regenerate on a nixpkgs/formatelf bump (keep in
# sync with pins/store.nix).
system:
let
  # `{ path = true; }` context makes Nix treat the string as a substitutable
  # store path without evaluating or fetching anything.
  fake =
    p:
    builtins.appendContext p {
      ${p} = {
        path = true;
      };
    };
in
{
  x86_64-linux = {
    glibc = fake "/nix/store/0d8g8n0a11v6f5m2h416ajyxmnkwc3md-glibc-2.42-67";
    gccLib = fake "/nix/store/r48746qznwqxxl9qzd8f08ny8mg1dg2y-gcc-15.3.0-lib";
    zlib = fake "/nix/store/zks9mfsn4rqr6z9g6pcj2xqzcsplj0nb-zlib-1.3.2";
    zstd = fake "/nix/store/pxahscw9vl9vac1nbjpy6bhz3vbk3cpl-zstd-1.5.7";
    formatelf = fake "/nix/store/r6a970q9v1bzdfrd8dcqjmnfs94lh45g-formatelf-0-unstable-2026-08-11";
    # runtime deps for the ported packages (x86_64-only, so aarch64 omits them)
    ripgrep = fake "/nix/store/axp6zlky4x2v3jwcbq24a2cz25hzlw9b-ripgrep-15.2.0";
    coreutils = fake "/nix/store/97d5ygrvqj55f4nx1x34wfdcc7qn11c0-coreutils-9.11";
    # manylinux external libs for python wheels (glibc/gccLib/zlib already above)
    libffi = fake "/nix/store/wflv43s0i42ysmjvw1hiw4vdiidfzwnn-libffi-3.7.1";
    expat = fake "/nix/store/x7hyp2ndwysydy2q1djdvjzlqzvqhg8x-expat-2.8.2";
    ncurses = fake "/nix/store/zlvs6miv8wfki399pmxri7x0sjd3429c-ncurses-6.6";
    openssl = fake "/nix/store/1mf3lj0mldr8732yvzjc12fig2407b3d-openssl-3.6.3";
    opensslDev = fake "/nix/store/jvnhc1z9c04n4a7b2z2hzbajsa5i6ygd-openssl-3.6.3-dev";
    sqlite = fake "/nix/store/fqkp26idpnpqk5l2cjfb51jdn6nj5bam-sqlite-3.53.3";
    sqliteDev = fake "/nix/store/3jcwbrr7fg5jmyiw8xw02i3lw978mgq1-sqlite-3.53.3-dev";
    pkgConfig = fake "/nix/store/0v0raqk1qw5g2a21km4xa1hwhaq4s976-pkg-config-wrapper-0.29.2";
    icu = fake "/nix/store/nv8jd3fvfv8p1d6dxflk1snfxzwabbm7-icu4c-78.3";
    icuDev = fake "/nix/store/ahpzhy9kw4w3wnva40n8bi6qlhn9frsy-icu4c-78.3-dev";
    bzip2 = fake "/nix/store/0hckf4kx70qifvrsbh64hc2s5xfyrf97-bzip2-1.0.8";
    xz = fake "/nix/store/96hgnqnikm0k4pag8x35hb6s46nag1l3-xz-5.8.3";
    bubblewrap = fake "/nix/store/lqndphylsxqwbwm804n473pb4sqb98sh-bubblewrap-0.11.2";
    socat = fake "/nix/store/b6jsx5bi7n3hhfmdlhczl60ssvyphj3g-socat-1.8.1.3";
  };
  aarch64-linux = {
    glibc = fake "/nix/store/f8q4w2hbjvwy7qqwpnvbf5f4qwyww6cp-glibc-2.42-67";
    gccLib = fake "/nix/store/ylzalvsf8nxhidm1p72k6ckxckpj1wd3-gcc-15.3.0-lib";
    zlib = fake "/nix/store/3v2w5hdrpzwx3w8svda35lyrq9jwqbc8-zlib-1.3.2";
    zstd = fake "/nix/store/k2fr8pihnym47m71fij3ns184vbx4v79-zstd-1.5.7";
    formatelf = fake "/nix/store/hk6nkaqbxlyymm91gw9v3rr5b88z0mqy-formatelf-0-unstable-2026-08-11";
  };
}
.${system}
