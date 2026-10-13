%dw 2.0
import try, fail from dw::Runtime
import hashWith from dw::Crypto
import toHex from dw::core::Binaries
import modules::Masking

// MySQL 8 TIMESTAMP bounds, checked after conversion to UTC and before truncation.
fun storageTimestamp(value) = try(() -> do {
  var utc = (value as DateTime) >> "UTC"
  ---
  if (utc < |1970-01-01T00:00:01Z| or utc > |2038-01-19T03:14:07Z|)
    fail("Timestamp outside MySQL storage range")
  else utc as String {format:"yyyy-MM-dd HH:mm:ss"}
})

fun canonical(v) = v match {
  case o is Object -> ((o pluck ((value,key) -> {key:key as String,value:canonical(value)})) orderBy $.key)
    reduce ((item,acc={}) -> acc ++ {(item.key):item.value})
  case a is Array -> a map canonical($)
  else -> v
}
fun normalized(env) = do {
  var e = env.event
  var f = env.final
  var stamp = storageTimestamp(e.eventTimestamp)
  var received = storageTimestamp(env.receivedAt)
  var hits = ((f.ruleHits default []) distinctBy $.ruleCode) orderBy $.ruleCode
  var safeEvent = e update {case c at .card.maskedCardNumber -> Masking::maskCard(c)}
  var safeEnvelope = (env -- ['event']) ++ {event:safeEvent}
  var core = {
    event: safeEvent, final: (f -- ['ruleHits']) ++ {ruleHits:hits}, policySnapshot: env.riskConfig default {},
    enrichmentIncomplete: env.enrichmentIncomplete default (f.enrichmentIncomplete default false),
    alertRequired: (env.alertRequired default false) or env.scoring.riskBand == "HIGH" or f.riskBand == "HIGH" or f.decision == "BLOCK"
  }
  ---
  if (e.eventId == null or f.decision == null or f.riskScore == null or Masking::hasPan(env))
    fail("Unsafe or incomplete finalized decision")
  else {
    eventId:e.eventId,transactionId:e.transaction.transactionId,
    eventTimestamp: if (stamp.success) stamp.result else if (received.success) received.result else "1970-01-01 00:00:01",
    timestampFallback: not stamp.success,
    customerId:e.customer.customerId,cardToken:e.card.cardToken,maskedCard:Masking::maskCard(e.card.maskedCardNumber),
    amount:e.transaction.amount,currency:e.transaction.currency,merchantId:e.merchant.merchantId default null,
    merchantCountry:e.merchant.merchantCountry default null,geoCountry:e.device.geoCountry default null,
    riskScore:f.riskScore,riskBand:f.riskBand,decision:f.decision,ruleHits:hits,
    correlationId:env.correlationId,policySnapshot:core.policySnapshot,enrichmentIncomplete:core.enrichmentIncomplete,
    alertRequired:core.alertRequired,envelope:safeEnvelope,
    decisionHash:toHex(hashWith(write(canonical(core),"application/json",{indent:false}) as Binary,"SHA-256"))
  }
}
