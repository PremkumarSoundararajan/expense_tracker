# Account deletion

Settings → **Delete account and app data** is available on Android, iOS and web.
The initial explanation and final confirmation are both required before deletion.

## What the implementation deletes

1. The locally saved active/Worker DB IDs after ownership/name/layout checks.
   Drive `files.delete` permanently
   deletes each file, including classification/category/target metadata tabs.
   Other Drive files and the Google account are untouched.
2. `/account/delete` verifies the Google access token with Google's userinfo
   endpoint. The authenticated `sub` determines the D1 owner; caller-supplied
   owner/mailbox identifiers are never trusted. It deletes retired OAuth states,
   email evidence/seen records, cancels Durable Object alarms and erases their
   storage, revokes previous email refresh tokens, and deletes those account rows.
   Failed revocations retain only disabled records for retry and return failure.
   Normal statement imports do not persist expenses or OAuth tokens in D1.
3. Account-scoped local expense cache/outbox, categories, baseline, merchant
   classifications/drafts and targets, and device-level budget history,
   currency, theme, summary preferences and reminders. Other users' scoped local
   ledger caches are preserved. Notification cancellation includes test alerts.
4. The current Google grant through Google's revocation endpoint; sign-out follows.

The client keeps a minimal local deletion journal (steps/file IDs, never tokens)
until completion. On restart it blocks normal ledger initialization and outbox
sync and offers Resume deletion. A failed operation is never labelled complete.
Deleting a spreadsheet is retryable: missing files are treated as already removed.
The backend capability is checked before irreversible operations.

## Limits disclosed to users

- Other devices' offline caches cannot be remotely wiped. Users should sign out
  and clear app/site data there; old builds must not be used to restore a ledger.
- Other ledger spreadsheets not saved on this device are not discovered or
  deleted automatically. Users should delete those files in Google Drive.
- Cloudflare recovery backups can retain deleted records for 7 days on Free or
  30 days on Paid. Google controls its own backend retention. Avoid claiming
  immediate erasure from all provider backups. Never restore a retired email DB
  backup into service without rerunning retirement cleanup before serving it.
- No Pocket Ledger account table exists in the current backend. Deletion removes
  its Google association/grants, ledger and remaining retired email owner records.
  Explicitly signing in again after completed deletion can create a new ledger.

## Deployment and store setup

1. Deploy the tested API first from `C:\Projects\pocket-ledger-api`:
   `npm run deploy`. Existing EMAIL_DB and EMAIL_SCAN_JOBS bindings are used;
   no schema migration or new secrets are required.
2. Build/publish the web app. `web/delete-account.html` becomes
   `https://pocket-ledger-cdn.pages.dev/delete-account.html`. It links to the web
   app's deletion flow, with support contact as an alternative. Test it signed out.
3. Put that URL in Google Play's account deletion/Data safety section and update
   the privacy policy to describe the actual retention and deletion behavior.
4. Create new Android and iOS builds with a higher build number. Test with a
   disposable Google account before release. App Review notes should point to
   Settings → Delete account and app data; demonstrate it last in the recording.

## Required physical-device verification (never use personal expense data)

- Add an expense, a custom category, merchant classifications, a target and a
  reminder to a disposable account. Keep an unrelated Google Sheet as a control.
- Cancel both screens and verify no data changes. Then confirm deletion.
- Verify real progress, no scheduled reminders, Google grant removal, spreadsheet
  absence, signed-out completion and the unrelated Sheet still present.
- Interrupt connectivity mid-deletion, relaunch and finish with Resume deletion;
  expired authorization should offer sign-out/sign-in to resume.
- Test Android, physical iPhone and web; include an account never connected to
  the retired email feature. Do not record personal account information.

Automated tests mock Google network calls and use an in-memory database; they do
not perform deletion against any real account.
