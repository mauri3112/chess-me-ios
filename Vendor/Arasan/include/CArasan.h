#pragma once
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef int (*ChessMeArasanCancel)(void *context);
typedef void (*ChessMeArasanUpdate)(const char *json, void *context);

// Synchronous, serialized in-process analysis. Call from a background task.
// Result codes: 0 success, 1 cancelled, 2 network error, 3 invalid position,
// 4 internal error. Callback strings are only valid for the callback duration.
int chessme_arasan_analyze(const char *network, const char *fen, const char *history,
                          const char *required_move, int depth, int hash_mb,
                          int milliseconds, uint64_t node_limit, void *context,
                          ChessMeArasanCancel cancel, ChessMeArasanUpdate update);

#ifdef __cplusplus
}
#endif
