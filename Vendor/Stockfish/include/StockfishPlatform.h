#pragma once
#define IS_64BIT
#define USE_POPCNT
#define NNUE_EMBEDDING_OFF
#if defined(__aarch64__) || defined(__arm64__)
#define USE_NEON 8
#if defined(__ARM_FEATURE_DOTPROD)
#define USE_NEON_DOTPROD
#endif
#elif defined(__SSE2__)
#define USE_SSE2 1
#endif
