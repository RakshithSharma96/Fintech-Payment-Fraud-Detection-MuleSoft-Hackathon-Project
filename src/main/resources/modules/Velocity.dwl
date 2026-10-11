%dw 2.0
/* Only intake modifies history; its single-concurrency source serializes the
   complete read/modify/write sequence on a single runtime instance. */
fun advance(history, eventId, epoch, windowSeconds) =
  (((history default []) filter ($.at > epoch - windowSeconds)) ++
    [{eventId: eventId, at: epoch}]) distinctBy $.eventId
