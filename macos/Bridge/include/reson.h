#ifndef RESON_H
#define RESON_H
#include <stddef.h>
#include <stdint.h>
/* Thin synchronous ABI, not real-time safe. Serialize every handle call.
   Path bytes are copied before return. All output buffers are caller-owned.
   Commands acknowledge asynchronously in snapshots. Destroy joins the worker;
   run it off the main UI thread, after all prior calls. Never reuse the handle.
   Valid aligned pointers and nonoverlapping buffers are the caller's obligation.
   Status: 0 OK, 1 invalid argument, 2 queue full, 3 disconnected,
   4 buffer too small, 5 internal failure. */
typedef struct ResonEngine ResonEngine;
typedef struct {
    uint64_t generation, acknowledged;
    uint32_t state; /* 0 empty, 1 loading, 2 playing, 3 paused, 4 stopped, 5 ended, 6 error */
    double position_seconds, duration_seconds; /* unknown duration = -1 */
    uint32_t sample_rate, channels, bit_depth; /* unknown = 0 */
} ResonSnapshot;
int32_t reson_engine_create(ResonEngine **out);
void reson_engine_destroy(ResonEngine *engine); /* null is a no-op */
int32_t reson_engine_load(ResonEngine *engine, const uint8_t *path, size_t length);
int32_t reson_engine_play(ResonEngine *engine);
int32_t reson_engine_pause(ResonEngine *engine);
int32_t reson_engine_stop(ResonEngine *engine);
/* JSON text plus NUL; required includes NUL. Query with text=NULL, capacity=0.
   Scalars are copied even when text is too small. Retry if text grew. */
int32_t reson_engine_snapshot(ResonEngine *engine, ResonSnapshot *out,
                            uint8_t *text, size_t capacity, size_t *required);
#endif
