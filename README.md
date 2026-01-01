# Node.js v22 on PowerPC G5 (Mac OS X Leopard) - Build Fixes

## Target System
- **Hardware**: Power Mac G5 Dual 2.0GHz (PowerPC 970)
- **OS**: Mac OS X Leopard 10.5.8 (Darwin 9.8.0)
- **Compiler**: GCC 10.5.0 (cross-compiled for PPC)
- **Architecture**: PowerPC 64-bit Big Endian

## Prerequisites
- GCC 10.5.0 installed in `/usr/local/gcc-10/`
- Python 3.7+ for build scripts
- Node.js v22.12.0 source

## Key Fixes

### 1. 64-bit Mode Compilation
The G5 defaults to 32-bit mode but V8 requires 64-bit for `V8_TARGET_ARCH_PPC64`.

**Fix**: Add `-m64` to all CFLAGS in makefiles and replace `-arch i386` with `-m64`:

```bash
# In all *.target.mk files:
sed -i 's/-arch i386/-m64/g' out/*.target.mk out/*/*.target.mk out/deps/*/*.target.mk
```

### 2. C++20 Standard
Node.js v22 requires C++20 features.

**Fix**: Add `-std=gnu++20` to all CFLAGS_CC_Release in makefiles.

### 3. Missing C++ Runtime Symbols
GCC 10's libstdc++ is 32-bit only. Use system libstdc++ with compatibility shims.

**Create `stdc++_compat.cpp`** (compile with `-fno-exceptions`):
```cpp
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
```

**Compile and add to link**:
```bash
/usr/local/gcc-10/bin/g++ -m64 -fno-exceptions -c stdc++_compat.cpp -o stdc++_compat.o
```

### 4. PPC64 GPR Save/Restore Functions
The 64-bit build requires register save/restore functions not in system libgcc.

**Create `ppc64_gpr.s`**:
```asm
.text
.align 2
.globl _saveGPR
.globl saveGPR
_saveGPR:
saveGPR:
    std r14,-144(r1); std r15,-136(r1); std r16,-128(r1); std r17,-120(r1)
    std r18,-112(r1); std r19,-104(r1); std r20,-96(r1); std r21,-88(r1)
    std r22,-80(r1); std r23,-72(r1); std r24,-64(r1); std r25,-56(r1)
    std r26,-48(r1); std r27,-40(r1); std r28,-32(r1); std r29,-24(r1)
    std r30,-16(r1); std r31,-8(r1); blr
.globl _restGPR
.globl restGPR
_restGPR:
restGPR:
    ld r14,-144(r1); ld r15,-136(r1); ld r16,-128(r1); ld r17,-120(r1)
    ld r18,-112(r1); ld r19,-104(r1); ld r20,-96(r1); ld r21,-88(r1)
    ld r22,-80(r1); ld r23,-72(r1); ld r24,-64(r1); ld r25,-56(r1)
    ld r26,-48(r1); ld r27,-40(r1); ld r28,-32(r1); ld r29,-24(r1)
    ld r30,-16(r1); ld r31,-8(r1); blr
.globl _restGPRx
.globl restGPRx
_restGPRx:
restGPRx:
    ld r14,-144(r1); ld r15,-136(r1); ld r16,-128(r1); ld r17,-120(r1)
    ld r18,-112(r1); ld r19,-104(r1); ld r20,-96(r1); ld r21,-88(r1)
    ld r22,-80(r1); ld r23,-72(r1); ld r24,-64(r1); ld r25,-56(r1)
    ld r26,-48(r1); ld r27,-40(r1); ld r28,-32(r1); ld r29,-24(r1)
    ld r30,-16(r1); ld r31,-8(r1); ld r0,16(r1); mtlr r0; blr
```

**Assemble**:
```bash
/usr/local/gcc-10/bin/gcc -m64 -c ppc64_gpr.s -o ppc64_gpr.o
```

### 5. OpenSSL Configuration
Use `linux-ppc64` with `no-asm` configuration for Big Endian PPC.

**Create `deps/openssl/config/archs/linux-ppc64/no-asm/crypto/buildinf.h`**:
```c
#define PLATFORM "platform: linux-ppc64"
#define DATE "built on: reproducible build"
static const char compiler_flags[] = {'g','c','c','-','1','0',' ','-','m','6','4','\0'};
```

### 6. Complete OpenSSL Headers
Copy all OpenSSL headers to the config-specific include directory:

```bash
for f in deps/openssl/openssl/include/openssl/*.h; do
    name=$(basename $f)
    if [ ! -f deps/openssl/config/archs/linux-ppc64/no-asm/include/openssl/$name ]; then
        cp $f deps/openssl/config/archs/linux-ppc64/no-asm/include/openssl/
    fi
done
```

### 7. LIBS Modification
Update makefile LIBS to use system libstdc++:

```makefile
LIBS := \
    -L/usr/lib -lstdc++.6 -lm
```

Add compat objects to LD_INPUTS in all linking targets:
```makefile
LD_INPUTS := \
    ... \
    /path/to/stdc++_compat.o \
    /path/to/ppc64_gpr.o
```

### 8. node_js2c 64-bit Crash Workaround
The `node_js2c` tool crashes with a segfault in strlen() on PPC64 Big Endian due to a 64-bit pointer alignment bug in libuv's directory entry handling.

**Error symptom**: Crash at address like `0x2e6363002f746d70` (contains ASCII bytes)

**Workaround**: Use Python `js2c.py` replacement. See `js2c.py` in this repo.

**Modify `out/libnode.target.mk`**:
```makefile
# Change line 7 from:
cmd_...node_js2c = ... "$(builddir)/node_js2c" "$(obj)/gen/node_javascript.cc" ...
# To:
cmd_...node_js2c = ... python3 ./js2c.py "$(obj)/gen/node_javascript.cc" ...

# Also remove $(builddir)/node_js2c dependency from line 27
```

### 9. Global __int128 Charconv Fix
GCC 10's `<charconv>` header has a template bug with `__int128` on PPC64 Big Endian. This affects multiple files.

**Error symptom**:
```
error: '__size' is not a member of 'std::__make_unsigned_selector_base::_List<>'
```

**Fix Part A**: Add `-D__SIZEOF_INT128__=0` to CFLAGS_Release in **ALL** `*.target.mk` files.
Note: `-U` doesn't work for builtin compiler macros; must redefine to 0.
```bash
# Apply to all target.mk files
find out -name "*.target.mk" -exec sed -i 's/CFLAGS_Release := \\/CFLAGS_Release := \\\n\t-D__SIZEOF_INT128__=0 \\/' {} \;
```

### 10. Ada Library Charconv Source Patch (Critical)
The `-D__SIZEOF_INT128__=0` flag helps but isn't enough for ada.cpp which directly includes `<charconv>`.
The ada URL parser needs custom `to_chars` and `from_chars` implementations for PPC64 BE.

**Patch `deps/ada/ada.h`** - Add at the VERY TOP of the file (before any includes):
```cpp
// PPC64 Big Endian workaround: GCC 10 charconv has broken __int128 template
// Must be at the very top before any other includes
#if defined(__powerpc64__) && defined(__BIG_ENDIAN__)
#include <cstdio>
#include <cstdlib>
#include <cerrno>
namespace std {
    struct to_chars_result {
        char* ptr;
        std::errc ec;
    };
    struct from_chars_result {
        const char* ptr;
        std::errc ec;
    };
    // to_chars - number to string
    template<typename T>
    inline to_chars_result to_chars(char* first, char* last, T value, int base = 10) {
        char fmt[8] = "%";
        if (base == 16) strcat(fmt, "llx");
        else strcat(fmt, "lld");
        int len = snprintf(first, last - first, fmt, (long long)value);
        if (len < 0 || len >= last - first) {
            return {last, std::errc::value_too_large};
        }
        return {first + len, {}};
    }
    // from_chars - string to number (overloads for different types)
    inline from_chars_result from_chars(const char* first, const char* last, int& value, int base = 10) {
        char* end;
        errno = 0;
        long v = strtol(first, &end, base);
        if (errno == ERANGE) return {first, std::errc::result_out_of_range};
        if (end == first) return {first, std::errc::invalid_argument};
        value = (int)v;
        return {end, {}};
    }
    inline from_chars_result from_chars(const char* first, const char* last, uint16_t& value, int base = 10) {
        char* end;
        errno = 0;
        unsigned long v = strtoul(first, &end, base);
        if (errno == ERANGE || v > 65535) return {first, std::errc::result_out_of_range};
        if (end == first) return {first, std::errc::invalid_argument};
        value = (uint16_t)v;
        return {end, {}};
    }
    inline from_chars_result from_chars(const char* first, const char* last, uint32_t& value, int base = 10) {
        char* end;
        errno = 0;
        unsigned long v = strtoul(first, &end, base);
        if (errno == ERANGE) return {first, std::errc::result_out_of_range};
        if (end == first) return {first, std::errc::invalid_argument};
        value = (uint32_t)v;
        return {end, {}};
    }
    inline from_chars_result from_chars(const char* first, const char* last, uint64_t& value, int base = 10) {
        char* end;
        errno = 0;
        unsigned long long v = strtoull(first, &end, base);
        if (errno == ERANGE) return {first, std::errc::result_out_of_range};
        if (end == first) return {first, std::errc::invalid_argument};
        value = (uint64_t)v;
        return {end, {}};
    }
}
#define ADA_PPC64_CHARCONV_DEFINED 1
#else
// Normal platforms use standard charconv
#endif
```

**Patch `deps/ada/ada.cpp`** - Find and comment out the charconv include:
```cpp
// Original:
#include <charconv>
// Change to:
#ifndef ADA_PPC64_CHARCONV_DEFINED
#include <charconv>
#endif
```

This provides a complete fallback using snprintf/strtol for PPC64 Big Endian systems.

### 11. Debug Format Fix (Darwin Assembler)
GCC 10 with `-gdwarf-2` generates `.4byte` pseudo-ops that Darwin's assembler doesn't understand.

**Error symptom**:
```
/var/tmp//ccXXXXXX.s:3650:Unknown pseudo-op: .4byte
```

**Fix**: Replace `-gdwarf-2` with `-gstabs+` in all makefiles:
```bash
find out -name "*.target.mk" -exec sed -i "" 's/-gdwarf-2/-gstabs+/g' {} \;
```

The stabs debug format is fully compatible with Darwin's assembler.

## Configure Command
```bash
./configure \
    --openssl-no-asm \
    --without-inspector \
    --without-intl \
    --dest-cpu=ppc64 \
    --dest-os=mac
```

## Build Command
After applying all fixes, build from the `out` directory to avoid reconfiguration:
```bash
cd out && make BUILDTYPE=Release V=1
```

## Automated Fix Script
Run after `./configure` and before `make`:

```bash
#!/bin/bash
cd out

# Fix arch flags
find . -name '*.target.mk' -exec sed -i 's/-arch i386/-m64/g' {} \;

# Add C++20 to all targets
find . -name '*.target.mk' -exec sed -i 's/CFLAGS_CC_Release :=/CFLAGS_CC_Release := -std=gnu++20/g' {} \;

# Fix global __int128 issue (affects ada, cares_wrap, etc.)
# Note: Must use -D...=0, not -U (doesn't work for builtin macros)
find . -name "*.target.mk" -exec sed -i 's/CFLAGS_Release := \\/CFLAGS_Release := \\\n\t-D__SIZEOF_INT128__=0 \\/' {} \;

# Fix debug format - Darwin assembler doesn't understand .4byte
find . -name "*.target.mk" -exec sed -i 's/-gdwarf-2/-gstabs+/g' {} \;

# Replace node_js2c with Python workaround (run from source root)
python3 -c "
with open('out/libnode.target.mk', 'r') as f:
    c = f.read()
c = c.replace('\"$(builddir)/node_js2c\" \"$(obj)/gen/node_javascript.cc\"', 'python3 ./js2c.py \"$(obj)/gen/node_javascript.cc\"')
c = c.replace('$(builddir)/node_js2c $(srcdir)', '$(srcdir)')
with open('out/libnode.target.mk', 'w') as f:
    f.write(c)
"

echo "Fixes applied!"
```

## Known Issues
- V8 may have additional PPC64 Big Endian compatibility issues
- Some tests may fail due to platform-specific assumptions
- Inspector/debugging features are disabled
- The `__SIZEOF_INT128__` redefinition produces harmless warnings

## Status
**Build Progress**: 1400+ objects compiled (January 2025)
- ✅ OpenSSL - Complete
- ✅ ada URL parser - Complete (with charconv patch)
- ✅ brotli compression - Complete
- ✅ sqlite - Complete
- ✅ ngtcp2 (QUIC) - In progress
- 🔄 V8 JavaScript engine - Building
- ⏳ Node core - Pending

## Files in This Repository
- `stdc++_compat.cpp` - C++ runtime shims for 64-bit PPC
- `ppc64_gpr.s` - PPC64 GPR save/restore assembly
- `js2c.py` - Python replacement for crashed node_js2c tool
- `buildinf.h` - OpenSSL build info header

## Author
Built with Claude Code assistance for the RustChain/Sophiacord project.
GitHub: https://github.com/Scottcjn/node-ppc
