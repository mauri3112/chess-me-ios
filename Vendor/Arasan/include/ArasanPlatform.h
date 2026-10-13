#pragma once

#if defined(__APPLE__)
#include <TargetConditionals.h>
#if TARGET_OS_OSX
#define _MAC
#endif
#endif
#define SIMD
#if defined(__aarch64__) || defined(__arm64__)
#define NEON
#else
#define SSE2
#endif
