// Exact AVX-512BW equivalents of the VNNI dot-product intrinsics, whose LLVM
// signatures in nixpkgs' rustc disagree with stdarch's declarations.
#[cfg(target_arch = "x86_64")]
#[allow(dead_code)]
pub(crate) mod nix_vnni_shim {
    use std::arch::x86_64::*;

    #[inline]
    #[target_feature(enable = "avx512f,avx512bw")]
    pub fn dpbusd(src: __m512i, a: __m512i, b: __m512i) -> __m512i {
        let lo = _mm512_set1_epi16(0xff);
        let a_even = _mm512_and_si512(a, lo);
        let a_odd = _mm512_srli_epi16::<8>(a);
        let b_even = _mm512_srai_epi16::<8>(_mm512_slli_epi16::<8>(b));
        let b_odd = _mm512_srai_epi16::<8>(b);
        let even = _mm512_madd_epi16(a_even, b_even);
        let odd = _mm512_madd_epi16(a_odd, b_odd);
        _mm512_add_epi32(src, _mm512_add_epi32(even, odd))
    }

    #[inline]
    #[target_feature(enable = "avx512f,avx512bw")]
    pub fn dpwssd(src: __m512i, a: __m512i, b: __m512i) -> __m512i {
        _mm512_add_epi32(src, _mm512_madd_epi16(a, b))
    }
}
