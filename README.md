# expense_tracker

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Publishing to Google Play

The Android release bundle is signed with the local upload key configured in
`android/key.properties`. The keystore and properties file are ignored by Git;
keep secure backups of both. If the upload key is lost, Play Console will
require an upload-key reset before future updates can be submitted.

Build the Play bundle with:

```shell
flutter build appbundle --release
```

The bundle is written to
`build/app/outputs/bundle/release/app-release.aab`. Upload it from a Play
Console testing or production release, not from the Store listing editor.

Google Sign-In also requires the upload certificate's SHA-1 to be registered
with the OAuth Android client. If Play App Signing is enabled, register the
Play app-signing certificate's SHA-1 as well for installs delivered by Google
Play.

## Cloudflare CSV sync

In the Flutter Web dashboard, use the spreadsheet button to save a Google
Spreadsheet ID or URL, or create a new spreadsheet. The cloud-upload button
sends the current ledger as CSV to `https://pocket-ledger-api.ledgerapi.workers.dev`
using the signed-in user's Google OAuth access token. The spreadsheet ID is
stored in browser preferences per Google account; access tokens are not stored.

The Worker must allow the deployed web app's origin and the `Authorization`,
`Content-Type`, and `X-Spreadsheet-ID` request headers for its CORS preflight.
For statements with a signed Amount column containing both signs, imports treat
negative values as expenses and omit positive credits. Separate Debit and
Credit columns use the Debit values and omit credits; positive-only Amount
exports remain supported, with recognizable income descriptions filtered.

## Financial baseline

**Insights** opens the merchant-first Financial Baseline work list. It
reuses Favourite Spending Spots consolidation and defaults to merchants covering
80% of recorded net spending. Fully classified merchants (Category, Essentiality,
and known Expense Type on every transaction) leave the work list but remain
available under **Review classified**. At 80% fully classified, the default view
shows an optional stopping point. **Review remaining** includes all unfinished
merchants, ranked by total spending. Budget warnings link straight to this view,
including merchants beyond the 80% target. Users can choose Top 15, 75%, 90%, or All,
search the selected view, and expand any row to inspect its transactions. Category and
Essential/Potentially Flexible choices apply to a merchant; transaction choices
are explicit exceptions. Changing merchant defaults preserves exceptions unless
"Apply to all, including exceptions" is confirmed. Unfinished edits survive in
an account-local draft; Save changes commits them and Discard clears the draft.

Category and essentiality are independent from Regular, Planned Occasional,
Unexpected Occasional, and Unknown Expense Type. Reviewing a merchant does not
silently change its transactions' frequency or remove existing budget coverage
warnings. Unreviewed merchants retain their existing suggestions/legacy mappings.

Committed choices and transaction exceptions are stored per account locally and
as stable-ID JSON records in a **Merchant Classifications** metadata tab. Existing
**Financial Baseline** mappings remain readable as a fallback; explicit master
choices and transaction exceptions take precedence. Insights use the effective
classified ledger. The existing baseline averages and budget formulas are not
changed. Spending trends, favourite spots, baseline insights/reductions, targets,
and suggested-budget details are opened through compact links below the table.

Category changes are projected to Sheet1 Category/Category ID cells using batched
writes. Transaction IDs are resolved again just before writing, so shifted or
deleted sheet rows are not addressed using cached row numbers. Dates, amounts,
raw descriptions, Expense Types, and transaction IDs are preserved. Metadata and
category sync retry after failures; local changes remain available offline.
Unrelated remote metadata records survive synchronization.

New matching descriptions reuse saved merchant defaults. Import review uses the
same spending-spot family resolver; the Worker also applies exact normalized
aliases and retains explicit reviewed categories as transaction exceptions.
Ambiguous matches stay unresolved rather than guessing. Other insight date
windows and transfer/refund eligibility rules remain in place.

Deploy the updated **pocket-ledger-api Worker before releasing the Flutter/web
app**. The app checks the Worker's `merchantClassificationReview` capability
before statement import, preventing silent use of an older classification path.

## iOS / TestFlight

See [the Windows-to-iOS release guide](docs/ios-release.md) for Google sign-in configuration, manual Codemagic compile/TestFlight workflows, signing setup, and the first-device test checklist.
