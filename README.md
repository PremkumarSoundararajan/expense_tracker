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

Open **My Financial Baseline** from the dashboard to map normalized ledger
merchants directly to Essential, Committed, or Discretionary. The unassigned
merchant pool and search are at the top; tap a merchant to choose a group, or
select multiple merchants and batch-assign them. These direct mappings are
independent from each transaction's existing Regular, Planned Occasional, or
Unexpected Occasional frequency. Transfers, card payments, refunds, and
reversals are excluded from baseline totals and internal transfers are tagged
as Transfers.

Rules are saved per Google account in local preferences and synchronized to a
`Financial Baseline` metadata tab in the `Expense Tracker DB` spreadsheet.
Monthly averages span the first through last calendar month in the ledger,
including months with no matching transactions; normalized annual amounts are
the monthly averages multiplied by 12.

The merchant pool shows each discovered normalized merchant's occurrence count
and average amount. Monthly group totals and averages update as mappings
change. Pocket Ledger checks the expected row-one headers before reading or
writing connected sheets and reports a layout error if they are missing or
modified.
