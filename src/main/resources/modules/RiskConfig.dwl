%dw 2.0
import fail from dw::Runtime
/* Object ++ can retain duplicate keys. Remove overridden keys before merging
   so validation and subsequent Java conversion inspect the same policy. */
fun override(base, changes) =
  validate((base -- (keysOf(changes) map ($ as String))) ++ changes)
fun validate(c) = do {
  var weights = [c.wAmount,c.wGeo,c.wVelocity,c.wMerchant,c.wHour,c.wWatchlist]
  var numbers = weights ++ [c.amountLimit,c.velocityMax,c.mediumMin,c.highMin,c.blockMin,c.failSafeScore,c.usualHourStart,c.usualHourEnd]
  var numeric = sizeOf(numbers filter ($ is Number)) == sizeOf(numbers)
  var valid = if (not numeric) false else
    c.amountLimit > 0 and c.velocityMax >= 1 and floor(c.velocityMax) == c.velocityMax
    and c.mediumMin > 0 and c.mediumMin < c.highMin and c.highMin <= 100
    and c.blockMin >= c.highMin and c.blockMin <= 100
    and c.failSafeScore >= c.mediumMin and c.failSafeScore <= 100
    and floor(c.mediumMin) == c.mediumMin and floor(c.highMin) == c.highMin
    and floor(c.blockMin) == c.blockMin and floor(c.failSafeScore) == c.failSafeScore
    and c.usualHourStart >= 0 and c.usualHourStart <= 23
    and floor(c.usualHourStart) == c.usualHourStart
    and c.usualHourEnd >= 0 and c.usualHourEnd <= 23
    and floor(c.usualHourEnd) == c.usualHourEnd
    and sizeOf(weights filter ($ < 0 or $ > 100 or floor($) != $)) == 0
    and (c.highRiskCategories is Array)
    and sizeOf(c.highRiskCategories filter ($ is String and not isEmpty(trim($)))) == sizeOf(c.highRiskCategories)
  ---
  if (valid) (c -- ['highRiskCategories']) ++ {highRiskCategories: c.highRiskCategories map upper(trim($))}
  else fail("Invalid risk policy")
}
