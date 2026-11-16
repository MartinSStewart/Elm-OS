// tools/build-patched-eco.sh compiles eco's Utils.cpp with g++, whose inline std::vector code calls
// these two libstdc++ functions when a vector would outgrow its maximum size. The link uses libc++,
// which has neither, so they are defined here. Neither can happen in practice.
#include <cstdlib>

namespace std {
[[noreturn]] void __throw_logic_error(const char*) { abort(); }
[[noreturn]] void __throw_length_error(const char*) { abort(); }
}
