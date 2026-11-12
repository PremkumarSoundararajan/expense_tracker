# Optional web access

Both native Settings → Pocket Ledger Web and the Financial Baseline suggestion
use `pocketLedgerWebUrl` in `lib/services/pocket_ledger_web_access.dart`.
The default production URL is `https://pocket-ledger-cdn.pages.dev/`.
An intentional production URL change can be supplied at build time with
`--dart-define=POCKET_LEDGER_WEB_URL=https://your-production-host/`.

The suggestion appears on native Android/iOS when more than 20 normalized
merchants remain unclassified. Fully classified and intentionally NA merchants
do not contribute to that count. The count uses saved review membership, so
pending edits remain work until saved. No modal appears merely on visiting the
screen. The suggestion remains one compact inline card across group switches.

Dismissal is stored locally per account under the merchant preference key with
the `_desktop_suggestion_dismissed` suffix; it survives app restarts and does not
remove the Settings link. Flutter Web hides both entry points to avoid opening
the same experience again. Native desktop also hides the suggestion, while
retaining Settings access.

Opening uses the existing `url_launcher` dependency with
`LaunchMode.externalApplication`, never an embedded WebView. Both entry points
check the merchant store's local draft before launching. Unsaved edits require
a Stay and save first / Open web app choice; continuing keeps the local draft.
Existing pending sync is described separately in the link UI and confirmation.
The link never saves, discards, uploads, or synchronizes classification data.
Browser launch failures produce a brief error with the production address.

Changed files include the shared web-access service and widgets, local dismissal
helpers in `merchant_classification_store.dart`, the Baseline suggestion slot,
the Settings entry in `main.dart`, and web-access/navigation tests. No backend,
Google Sheets schema, merchant rule, budget, NA, or synchronization logic changes.
