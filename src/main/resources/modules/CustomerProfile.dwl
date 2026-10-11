%dw 2.0
fun normalize(rows, cfg) = do {
  var row = (rows default [])[0] default {}
  var start = row.usual_hour_start default cfg.usualHourStart
  var end = row.usual_hour_end default cfg.usualHourEnd
  var risk = if (row.risk_profile is String) upper(row.risk_profile) else "STANDARD"
  var hoursValid = if (start is Number and end is Number)
    start >= 0 and start <= 23 and end >= 0 and end <= 23 and floor(start) == start and floor(end) == end
    else false
  var complete = (not isEmpty(row)) and (['STANDARD','TRUSTED','WATCHLIST'] contains risk)
    and (row.risk_profile is String) and row.usual_hour_start != null and row.usual_hour_end != null and hoursValid
  ---
  {enrichmentIncomplete: not complete, profile: {
    riskProfile: if (['STANDARD','TRUSTED','WATCHLIST'] contains risk) risk else "STANDARD",
    usualHourStart: if (hoursValid) start else cfg.usualHourStart,
    usualHourEnd: if (hoursValid) end else cfg.usualHourEnd
  }}
}
