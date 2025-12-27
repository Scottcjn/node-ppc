# Node.js v22 PowerPC Leopard (Mac OS X 10.5.8) Patches

## Build Environment
- **Target**: PowerPC G5 (32-bit mode)
- **OS**: Mac OS X 10.5.8 (Leopard)
- **Compiler**: GCC 10.5.0 at `/usr/local/gcc-10/bin/`
- **Build Date**: December 27, 2025

## Required Compiler Flags
```bash
export CC="/usr/local/gcc-10/bin/gcc -mlongcall -fno-reorder-blocks-and-partition"
export CXX="/usr/local/gcc-10/bin/g++ -mlongcall -fno-reorder-blocks-and-partition"
```

### Flag Explanations:
- **`-mlongcall`**: Required because the final binary exceeds the PowerPC branch instruction's ±16MB range limit.
- **`-fno-reorder-blocks-and-partition`**: **CRITICAL** - Prevents GCC from splitting code into `__text` and `__text_cold` sections. Without this, the linker places stub islands at section boundaries, causing "bl out of range" errors when cold code (33MB away) tries to call stubs at the start of `__text`.

## Patches Applied

### 1. config.gypi Modifications

**File**: `config.gypi`

**Changes**:
- Added `'python': 'python3'` to variables section (required for gyp)
- Changed `'host_arch': 'ppc64'` to `'host_arch': 'ppc'` (fixes V8 32-bit assertion)
- Added `'cflags': ['-mlongcall', '-fno-reorder-blocks-and-partition']` to target_defaults

### 2. QUIC ngtcp2_ssize Type Mismatch Fix

**File**: `src/quic/application.cc`

**Problem**: `ssize_t*` cannot convert to `ngtcp2_ssize*` on 32-bit PowerPC because:
- `ssize_t` is `long int` (4 bytes on 32-bit)
- `ngtcp2_ssize` is `ptrdiff_t` which is `int` (4 bytes)
- Same size but different types - compiler rejects pointer conversion

**Fix** (lines 284-299):
```cpp
ssize_t Session::Application::WriteVStream(PathStorage* path,
                                           uint8_t* buf,
                                           ssize_t* ndatalen,
                                           const StreamData& stream_data) {
  CHECK_LE(stream_data.count, kMaxVectorCount);
  uint32_t flags = NGTCP2_WRITE_STREAM_FLAG_NONE;
  if (stream_data.remaining > 0) flags |= NGTCP2_WRITE_STREAM_FLAG_MORE;
  if (stream_data.fin) flags |= NGTCP2_WRITE_STREAM_FLAG_FIN;
  /* PowerPC Leopard fix: ngtcp2_ssize is ptrdiff_t (int), ssize_t is long */
  ngtcp2_ssize ngtcp2_datalen = 0;
  ssize_t ret =
      ngtcp2_conn_writev_stream(*session_,
                                &path->path,
                                nullptr,
                                buf,
                                ngtcp2_conn_get_max_udp_payload_size(*session_),
                                &ngtcp2_datalen,  // Use local variable
                                flags,
                                stream_data.id,
                                stream_data.buf,
                                stream_data.count,
                                uv_hrtime());
  if (ndatalen) *ndatalen = static_cast<ssize_t>(ngtcp2_datalen);
  return ret;
}
```

### 3. V8 Platform Header ICE Fix

**File**: `deps/v8/include/v8-platform.h`

**Problem**: GCC 10 internal compiler error (Bus error) when compiling inline virtual functions with `-O3` and `-mlongcall`.

**Fix**: Add `__attribute__((optimize("O0")))` to affected virtual functions:

```cpp
// Line 1081
virtual void __attribute__((optimize("O0"))) CallOnWorkerThread(std::unique_ptr<Task> task) {

// Line 1094
virtual void __attribute__((optimize("O0"))) CallBlockingTaskOnWorkerThread(std::unique_ptr<Task> task) {

// Line 1108
virtual void __attribute__((optimize("O0"))) CallLowPriorityTaskOnWorkerThread(std::unique_ptr<Task> task) {

// Line 1123
virtual void __attribute__((optimize("O0"))) CallDelayedOnWorkerThread(std::unique_ptr<Task> task,
```

### 4. QUIC AI_NUMERICSERV Fix

**File**: `src/quic/preferredaddress.cc`

**Problem**: `AI_NUMERICSERV` is a getaddrinfo flag that was added in Mac OS X 10.6. Leopard (10.5) doesn't have it.

**Fix** (after includes, before namespace):
```cpp
/* Leopard compatibility: AI_NUMERICSERV was added in Mac OS X 10.6 */
#ifndef AI_NUMERICSERV
#define AI_NUMERICSERV 0
#endif
```

### 5. V8 Platform POSIX Patches (from earlier session)

**Files**:
- `deps/v8/src/base/platform/platform-posix.cc` - Leopard POSIX compatibility
- `deps/v8/src/base/platform/platform-darwin.cc` - Leopard Darwin compatibility
- `deps/v8/src/base/platform/memory.h` - posix_memalign fallback for Leopard

### 6. libuv Patches (from earlier session)

Various patches for Leopard compatibility in the libuv event loop library.

### 7. OpenSSL Endianness Fix (from earlier session)

PowerPC big-endian configuration for OpenSSL.

## Build Command

```bash
cd ~/node-ppc
export CC="/usr/local/gcc-10/bin/gcc -mlongcall -fno-reorder-blocks-and-partition"
export CXX="/usr/local/gcc-10/bin/g++ -mlongcall -fno-reorder-blocks-and-partition"
make -j2
```

## Notes

- Build rate is approximately 1-3 files per minute due to `-mlongcall` overhead
- Total object files: ~2500+
- Build process takes several hours on G5 hardware
- Some template warnings about ignored attributes are harmless
- The "does not support X86" warning from GCC is normal (ignoring -arch i386 flag)
