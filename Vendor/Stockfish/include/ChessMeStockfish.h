// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef int (*chessme_sf_cancel)(void *context);
typedef void (*chessme_sf_update)(const char *json, void *context);
int chessme_stockfish_analyze(const char *network, const char *initial_fen, const char *uci_moves,
                             const char *required_move, int depth, int hash_mb, int milliseconds,
                             uint64_t nodes, int threads, void *context,
                             chessme_sf_cancel cancelled, chessme_sf_update update);
void chessme_stockfish_trim_memory(void);
#ifdef __cplusplus
}
#endif
