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

### 9. ada Library __int128 Charconv Fix
GCC 10's `<charconv>` header has a template bug with `__int128` on PPC64 Big Endian.

**Error symptom**:
```
error: '__size' is not a member of 'std::__make_unsigned_selector_base::_List<>'
```

**Fix**: Add `-U__SIZEOF_INT128__` to CFLAGS in `out/deps/ada/ada.target.mk`:
```makefile
CFLAGS_Release := \
    -U__SIZEOF_INT128__ \
    -O3 \
    ...
```

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

# Fix ada __int128 issue
sed -i 's/CFLAGS_Release := \\/CFLAGS_Release := \\\n\t-U__SIZEOF_INT128__ \\/' deps/ada/ada.target.mk

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

## Status
Build in progress - OpenSSL and dependencies completed, continuing with V8 and Node core.

## Files in This Repository
- `stdc++_compat.cpp` - C++ runtime shims for 64-bit PPC
- `ppc64_gpr.s` - PPC64 GPR save/restore assembly
- `js2c.py` - Python replacement for crashed node_js2c tool
- `buildinf.h` - OpenSSL build info header

## Author
Built with Claude Code assistance for the RustChain/Sophiacord project.
GitHub: https://github.com/Scottcjn/node-ppc
