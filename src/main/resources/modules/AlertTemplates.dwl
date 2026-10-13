%dw 2.0
import modules::Masking
fun fmt(n) = (n as Number) as String {format:"#,##0.00"}
fun one(e) = do {
 var p=e.event
 var f=e.final
 ---
 "Transaction ID: $(p.transaction.transactionId)\nEvent ID: $(p.eventId)\nDate and Time: $(p.eventTimestamp)\n" ++
 "Amount: $(p.transaction.currency) $(fmt(p.transaction.amount))\nCard: $(Masking::maskCard(p.card.maskedCardNumber)) ($(p.card.cardType default 'N/A'))\n" ++
 "Customer: $(p.customer.name default 'N/A') ($(p.customer.customerId))\nMerchant: $(p.merchant.merchantName default p.merchant.merchantId), $(p.merchant.merchantCountry default '--')\n" ++
 "Risk Score: $(f.riskScore) \u2013 Band $(f.riskBand)\nSystem Decision: $(f.decision)\nCorrelation ID: $(e.correlationId)\n\nTriggered Rules:\n" ++
 (((f.ruleHits default []) map (r) -> "- $(r.ruleCode) - $(r.ruleName) (weight $(r.ruleWeight))") joinBy "\n")
}
fun subject(kind, events, alertId) =
 if (kind == "AGGREGATE") "HIGH RISK Payments (AGGREGATED) \u2013 Card $(Masking::maskCard(events[0].event.card.maskedCardNumber)) \u2013 $(sizeOf(events)) transactions"
 else "HIGH RISK Payment \u2013 $(events[0].event.transaction.transactionId) \u2013 Score $(events[0].final.riskScore)"
fun body(kind, events, alertId) = Masking::sanitize(
 (if (kind == "AGGREGATE")
   "Multiple high-risk transactions were detected on card $(Masking::maskCard(events[0].event.card.maskedCardNumber)) within the alert throttling window.\nIndividual alerts were suppressed to avoid flooding the risk mailbox. ALL affected transactions are listed below.\n\n"
 else "A payment transaction has been flagged as high risk and requires review.\n\n") ++
 ((events map one($)) joinBy "\n\n--------------------\n\n") ++
 (if (kind == "AGGREGATE") "\n\nPlease action these transactions in the fraud review console.\n\nRegards,\nAutomated Fraud Monitoring"
 else "\n\nPlease action this transaction in the fraud review console.\n\nRegards,\nAutomated Fraud Monitoring"))
