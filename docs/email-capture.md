# Gmail scans

Settings connects one Gmail mailbox with read-only OAuth and sets optional reminder notifications. A reminder never starts a scan. Expenses starts a scan only when the user presses Start scan or Resume scan.

A scan is now a durable background job. It continues when the app closes. The screen polls progress while visible and reloads saved results on return. Pause scan explicitly pauses the server job. Failed jobs display Needs attention and can be resumed from their checkpoint.

Start new scan clears old unimported results and selects 1–30 days (7 recommended), or Since the last completed scan. Imported/excluded/uncertain-import records remain protected. A new job replaces old work with a new generation, preventing stale results from returning. Bank statements remain the route for longer periods.

The server lists up to 100 Gmail IDs, processes batches of 25 with five concurrent reads, caches the access token encrypted until near expiry, and batches database writes. Seen message IDs, parser version and skip reasons prevent unnecessary reprocessing. Unknown formats are read in full; only obvious non-receipts are rejected from metadata. Bodies prefer text/plain, with bounded HTML fallback.

The user reviews Category, Essentiality and Expense Type before approval. Evidence and verification notes open on demand. Nothing is added to Sheets by a background job. Duplicate detection, saved Settings currency, manual confirmation of review-only expenses, and uncertain-import protection remain enforced.

The Worker requires D1 migration 0004_background_email_jobs.sql and the EMAIL_SCAN_JOBS SQLite Durable Object binding. The deployed entry is src/worker.js. The current implementation does not need a cron or a paid-plan upgrade. See the API repository's docs/background-email-jobs.md and docs/email-job-performance.md for deployment details and benchmark limitations.

There is no completion push notification yet. Return to Expenses to see completed results. See email-detection-rules.md for parsing/currency limitations. PDF-only and image receipts are not OCR-parsed.

Only Gmail is supported. New jobs use the currency in app Settings as the fallback for unlabelled amounts; explicit receipt currencies are preserved, and no conversion is performed. Users can correct an individual receipt currency during review. Feedback in Settings opens an addressed message in the user’s email app; it does not send automatically.
