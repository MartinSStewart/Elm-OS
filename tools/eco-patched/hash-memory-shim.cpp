// libc++ 21's headers call std::__hash_memory for std::hash of strings and scalars; the libc++.a in
// eco's runtime bundle is older and lacks it. This stands in for it. Every caller in a program links
// to this one definition, so the hash is consistent.
#include <cstddef>
#include <cstdint>
#include <cstring>
namespace std { inline namespace __1 {
static inline uint64_t mix64(uint64_t h) {
    h ^= h >> 33; h *= 0xff51afd7ed558ccdULL;
    h ^= h >> 33; h *= 0xc4ceb9fe1a85ec53ULL;
    h ^= h >> 33;
    return h;
}
size_t __hash_memory(const void* p, size_t n) noexcept {
    const unsigned char* b = static_cast<const unsigned char*>(p);
    uint64_t h = 0x9e3779b97f4a7c15ULL ^ n;
    while (n >= 8) {
        uint64_t w; std::memcpy(&w, b, 8);
        h = mix64(h ^ w);
        b += 8; n -= 8;
    }
    uint64_t w = 0;
    std::memcpy(&w, b, n);
    return static_cast<size_t>(mix64(h ^ w));
}
}}
