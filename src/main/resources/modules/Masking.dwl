%dw 2.0
/* Keep only the last four characters; everything else becomes X. */
fun maskCard(s) = do {
  var str = (s default "") as String
  var n = sizeOf(str)
  ---
  if (n <= 4) "XXXX" else (((1 to (n - 4)) map "X") joinBy "") ++ str[-4 to -1]
}

/* Strip anything that looks like a raw card number from free text (error messages, reasons). */
fun sanitize(s) = (s default "") as String replace /(\d[ -]?){13,19}/ with "[REDACTED]"

/* Reject PAN-like values in every string field before storage or logging.
   Nested unknown fields are already prohibited by the JSON schema. */
fun hasPan(value) = value match {
  case obj is Object -> sizeOf((obj pluck ((v, k) -> hasPan(v))) filter $) > 0
  case arr is Array -> sizeOf(arr filter ((v) -> hasPan(v))) > 0
  case str is String -> sizeOf(str scan /(\d[ -]?){13,19}/) > 0
  else -> false
}
