> Scanning now uses durable background jobs. The parsing rules below still apply; older foreground implementation notes are historical. See [email-capture.md](email-capture.md) for the current flow.

# Current email expense detection rules (parser version 11)

This is a deterministic text parser. Gmail search is only candidate retrieval: a separate relevance check filters unrelated mail before choosing Ready to import or Needs review. Nothing is added to Sheets automatically.

## Candidate search and content

Search only the user's selected received-date range, excluding spam/trash. Candidate terms are receipt, invoice, payment, charged, debited, spent, order confirmation, subscription renewed, transaction amount, amount paid, you made, you sent, or Gmail category:purchases. Search is deliberately broader than acceptance: a matching invoice or booking is not proof of payment.

Prefer non-empty UTF-8 text/plain alternatives, with bounded text/html fallback, strip scripts/styles, preserve HTML cell/row/block boundaries and decode common/numeric entities. The current limits remain 64,000 characters, eight nesting levels and twenty child parts per node. PDF/image extraction, OCR and non-UTF-8 charset handling remain unsupported. Preferred multipart-alternative selection is now implemented. Messages with no eligible amount or only zero amounts are ignored. Conflicting or unsupported monetary evidence remains reviewable. Gmail-generated summary cards are not part of the message payload.

Require a receipt/invoice/payment/billing subject, direct transaction wording, a receipt-like attachment name, or eligible labeled amount evidence. Investing/newsletter-style subjects and bulk newsletters are not put in review merely because Gmail matched a generic word such as spent or payment. A transactional subject or direct payment evidence can still qualify a receipt that includes marketing/unsubscribe content. This is not a sender-domain trust list.

## Completion evidence

Accept recognized payment successful/completed/processed/confirmed/received/posted wording, including payment was received, payment has been received, thank you for your payment, we received your payment, and existing paid/charged/receipt/autopay phrases. A positive, eligible Amount paid, Current Amount Paid or Total paid value can establish completion by itself. Previous/prior amounts and zero values cannot.

The CVS retail pattern remains supported: a receipt subject, transaction-on date, and labeled purchase total. Transaction Amount is recognized as an amount label; alone it does not establish completion because it could be an authorization or unpaid order.

Scheduled/failed/declined/cancelled/refund/reversed notices and obvious transfers/card repayments remain review-only. A due subject or remaining balance can coexist with a current positive paid amount; due alone is not payment evidence. Future-charge wording is never converted into an automatic expense just by broadening the search.

Recognize completed narratives such as “Your payment of $234.40 has been received”, “We received your payment of $234.40”, and “You made a $320.00 transaction with GIDEON”. Narrative payment amounts use tier 1; conflicting values stay reviewable. A bank alert uses the merchant named in the transaction rather than the bank sender. Split HTML amount-label words are joined. Paid amounts in HTML tables are matched by header column; dates below headers are never treated as money. Conflicting paid rows require review.

Sent-money alerts such as “You sent $308.12 to Example Services” are extracted generically, including supported currency-code forms. The recipient is used instead of the bank sender when readable. They always enter Needs review as a possible transfer, with the amount shown as an unconfirmed suggestion. The user must confirm it was an expense, not movement between their own accounts or a card repayment. No bank/recipient names are hard-coded.

## Amount priority

| Tier | Eligible labels |
|---|---|
| 1 | Current Amount Paid, Amount paid, Amount charged, Transaction Amount, Total paid, Payment Amount, You paid, Charged |
| 2 | Grand Total, Service Total |
| 3 | Total spent (including this trip/today), Transaction Total, Purchase Total, Total |

Use the highest applicable tier. Identical repeats collapse; different amounts or currencies within that tier go to Needs review as amount_conflict. A lower-ranked different total does not veto a clear paid amount, but produces a warning to verify whether the ledger should record the charged amount or full purchase total.

Never match total inside subtotal. Previous/prior/remaining amounts, taxes, balance due, savings and rewards are not purchase totals. Zero is never used as the expense amount. An explicitly zero top-tier payment does not fall through to a larger lower-tier balance/total; it is ignored as no_amount. Invalid number formats in the highest tier also go to review, never to a guessed or truncated value.

Supported number forms remain ungrouped digits or Western comma grouping with up to two dot-decimal places. Decimal-comma, space/apostrophe grouping, Indian grouping and higher precision are not guessed. Supported currencies remain USD, CAD, AUD, EUR, GBP, INR, SGD and MYR. Supported explicit dollar prefixes override the mailbox default. A currency-less paid-amount label or bare dollar sign uses the mailbox currency with a visible verification warning. No FX conversion is performed.

## Dates and timezone

The app sends its IANA timezone when connecting or starting a scan. The server saves it with the scan range so a resumed scan keeps the original timezone even after travel. Older clients that send no timezone use the saved mailbox timezone (legacy accounts can still be UTC until scanned by an updated app).

- Preserve valid printed YYYY-MM-DD date-only values; they are calendar dates, not UTC instants to shift.
- Support the English transaction-on month/day/year form used by CVS.
- Support M/D/YY or M/D/YYYY timestamps with an AM/PM time and supported zone, such as 11/2/26 4:34am CST. Convert the instant into the user's timezone before choosing the calendar date. The supported named zones are UTC/GMT and North American EST/EDT/CST/CDT/MST/MDT/PST/PDT; numeric UTC offsets are also accepted. In this explicit M/D receipt format, CST is interpreted as US Central Standard Time (UTC-06:00) and flagged for verification because the abbreviation is ambiguous globally.
- Support Paid on Nov 10, inferring the year from the received date in the user's timezone. Paid on Dec 31 received in early January uses the previous year. Inferred years remain flagged; other future/ambiguous dates go to review.
- Otherwise use the received date in the user's timezone, marked for verification. Unsupported localized/non-Gregorian date formats are not guessed.

## Ready and Needs review lists

The UI provides Ready to import and Needs review buttons with counts. Each collapsed item has at most two text lines; expanding it shows classifications, verification warnings, evidence and editing. Status refresh also hides old missing/zero-only review drafts immediately, without accessing Gmail, and counts only the visible eligible drafts. Needs review shows short email evidence and reason codes such as no_completion_phrase, amount_conflict, unsupported_amount_format, unreadable_content, rejected_transfer and rejected_keyword:due.

A review-only email is not automatically eligible for import. If a single clear highest-priority amount was read but completion/date is uncertain, show it as Possible amount — verify and prefill the edit form. If amounts conflict, list the read amounts and labels without choosing one. Messages with no eligible amount are omitted from both lists. Unreadable/unsupported number formats are shown as source text, never converted to a guessed value.

The user opens it, verifies or enters valid merchant/amount/currency/date details, and explicitly confirms that it is a completed expense rather than a bill, hold, refund or transfer. Showing a possible amount does not waive this confirmation. Category, Essentiality and Expense Type remain editable inline. Backend validation requires manual confirmation too. The user can instead exclude the email without calling it an expense. Refunded amounts are not silently imported as positive purchases.

Previously skipped/pending/review-only messages can be re-evaluated when the parser version changes, through an explicit scan whose range includes the original receipt. Old unapproved newsletter and missing-amount false positives become ignored and their stored proposal payload is cleared; added, excluded and uncertain-in-flight records are preserved. Repeat scans reuse existing items and do not create duplicates. The inbox shows up to 200 entries per list; counts can include more, revealed as entries are resolved.

The client retries transient failures only for read-only status refreshes, up to two retries. It never blindly repeats a new-scan reset or approval request after a lost response. An acknowledged scan session can recover through its saved scan ID and checkpoint. On failure it preserves displayed/saved results and reports a paused scan rather than leaving a stale Scanning message. Status decryption reuses the configured non-extractable encryption key instead of importing one per draft; owner-bound authenticated decryption still applies per proposal.

## Remaining limits

Only English rules and the supported currencies/formats above are implemented. Refund credits, FX ledger fields, PDF/OCR, locale packs, stronger processor/P2P detection, and wider duplicate matching remain separate work. Same-date/amount/normalized-merchant checks flag possible duplicates; they are not proof of identity. Scanning starts manually, then runs as a durable background job with checkpoints. No external AI service reads emails.

The earlier [email-parser-audit.md](email-parser-audit.md) is retained as a historical audit; use this file for current parser behavior.

Bank alerts are hidden when exactly one vendor receipt matches normalized merchant, amount and currency within three calendar days, and sender domains are known and different. Ambiguous matches remain visible. Excluding the vendor draft reveals the bank alert again. Newly imported receipts retain only an encrypted minimal matching key, without subject/body evidence, for later alert matching. Previously imported receipts with cleared evidence cannot be matched this way; Sheets duplicate checks still apply during approval. Generic sent-money parsing tolerates HTML line breaks between words.

Email merchant names now use the Baseline fingerprint noise removal for store/reference numbers and recurring codes. Generic payment prose is trimmed before normalization. Existing drafts are cleaned on status refresh. Paused scans show their saved start/end dates; a new-scan selection does not change the resume range. The UI also reports hidden bank-alert counts.

Explicit Start new scan now clears unimported pending/review/ignored drafts and their seen markers, then commits the new dates before Gmail access. Added/excluded/uncertain-import records remain protected. New session IDs fence resume requests; a replaced request cannot restore old data. Gmail pages contain one message to reduce per-request CPU, with a 60-second scan lease. The app continues foreground pages automatically and retries transient interruptions only by resuming an acknowledged session. Completed scan ranges remain visible.
