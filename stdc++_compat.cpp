// Compatibility shims for missing libstdc++ symbols (64-bit PPC)
// Compiled with -fno-exceptions
#include <cstdlib>

namespace std {
  void __throw_bad_function_call() { abort(); }
}

void operator delete(void* ptr) noexcept { if (ptr) std::free(ptr); }
void operator delete(void* ptr, unsigned long) noexcept { if (ptr) std::free(ptr); }
void operator delete[](void* ptr) noexcept { if (ptr) std::free(ptr); }
void operator delete[](void* ptr, unsigned long) noexcept { if (ptr) std::free(ptr); }
void* operator new(unsigned long size) noexcept { return std::malloc(size ? size : 1); }
void* operator new[](unsigned long size) noexcept { return std::malloc(size ? size : 1); }
