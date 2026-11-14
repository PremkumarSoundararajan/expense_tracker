# iOS new Google account entry trial

Status: candidate workaround; must be verified on a real iPhone before release.

Observed: selecting a remembered account works. Google's account-entry page in the app stalls after email submission, before password entry. Normal and Private Safari work. Cancelling returns to Pocket Ledger. The underlying cause is not confirmed.

The iOS login screen now offers Use a different Google account. It collects only an email, passes it as Google's supported login hint to the same native GoogleSignIn SDK, and restores the resulting SDK session through the existing Flutter plugin. Google alone handles passwords, verification and consent. The hint is advisory: Google can still show an account chooser or email page, so this cannot be considered a confirmed fix without device testing.

No Flutter dependency versions, OAuth clients, scopes, Android code, backend or publishing settings were changed. Runner explicitly links the same GoogleSignIn 8.x package already required by google_sign_in_ios 5.9.0. No email, password, token or authentication URL is logged or stored by the new flow.

## Validate with Codemagic

Manually build branch fix/ios-google-account-entry using ios-testflight. Existing focused widget tests include the native channel's cancellation behavior and Android visibility. Cloud Linux does not have Flutter or Xcode, so those tests and native compilation must run on Codemagic.

On an iPhone test:

- Remembered account with the original button.
- Previously unlisted account using Use a different Google account, including password and consent.
- Cancel both the email dialog and Google window; then retry.
- Deny consent, retry and reconnect.
- Verify the selected account's ledger, Drive/Sheets permissions, expense writes and relaunch restoration.
- Confirm a different email never restores the previous account unexpectedly. Google controls final account selection.

If Google still stalls, capture device logs and the exact resolved GoogleSignIn/AppAuth versions; do not claim the workaround solved the root cause. Do not publish Android or deploy the backend for this trial.
