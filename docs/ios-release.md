# Pocket Ledger: iOS build and TestFlight setup from Windows

The repository now contains the iOS preparation work. A native iOS build has not yet been compiled or run: Windows cannot run Xcode. Start with the unsigned Codemagic workflow, then move to a signed TestFlight build once Google and Apple configuration is available.

## What is prepared

- Native iOS Google Sign-In reads its iOS client ID from Info.plist instead of receiving the web client ID from Dart. Android and web retain their existing configuration and Drive/Sheets scopes.
- Info.plist registers the matching reversed-client callback URL scheme. tool/configure_ios.dart derives both values together to avoid mismatch.
- AppDelegate registers the local notification delegate. The existing Dart service already requests iOS permissions when reminders are enabled and schedules local reminders; no push-notification backend or APNs entitlement is needed for these local reminders.
- Failed silent credential restoration returns to sign-in so a user can retry.
- iOS-only launcher icon generation uses the existing Pocket Ledger artwork, removes alpha, and leaves Android/web icon generation alone.
- codemagic.yaml has a manual unsigned compile check and a separate signed IPA/TestFlight upload workflow. Neither has automatic commit triggers. Neither submits the app for public release.
- iOS deployment target remains 15.0. The existing Swift Package Manager integration is retained; the installed native plugins include SwiftPM support. Do not add a Podfile merely because older setup guides mention one.

## 1. Google iOS OAuth client

The client you supplied is now configured locally:

``832232205995-ob08konqbo58iko9rvj586gf7g77bg11.apps.googleusercontent.com``

Set GOOGLE_IOS_CLIENT_ID to that exact value in Codemagic too. The generated local xcconfig is ignored by Git, so it will not arrive on the cloud runner automatically. The steps below explain how to recreate or replace it.

Use the same Google Cloud project that owns the existing Pocket Ledger web/Android OAuth clients and Sheets/Drive consent configuration.

1. Open Google Cloud Console, then Google Auth Platform > Clients (or APIs & Services > Credentials).
2. Create an OAuth client with application type iOS.
3. Set the bundle ID to com.premkumar.pocketledger, exactly matching the Xcode project.
4. Copy its client ID ending in .apps.googleusercontent.com. This is a public identifier; do not provide an OAuth client secret. A web or Android client ID cannot substitute for the iOS client ID.
5. From C:\Projects\expense_tracker in PowerShell, run:

```powershell
dart run tool/configure_ios.dart --client-id=YOUR_IOS_CLIENT_ID.apps.googleusercontent.com
```

Use the full real client ID in place of the example. The helper creates ios/Flutter/GoogleSignIn.xcconfig with the client ID and matching reversed ID. Both Debug.xcconfig and Release.xcconfig include it, so Profile builds inherit it too. This generated file is ignored by Git and recreated in CI. You do not need to add Firebase or download a client-secret JSON file.

Alternatively set GOOGLE_IOS_CLIENT_ID in the process environment and run:

```powershell
dart run tool/configure_ios.dart
```

The helper validates formatting, rejects Pocket Ledger's known web client, and validates before writing so invalid input leaves an existing configuration intact. It cannot verify with Google that another syntactically valid ID is actually registered as an iOS client; check its application type and bundle ID in the console.

Documentation: https://developers.google.com/identity/sign-in/ios/start-integrating

## 2. Connect the source repository to Codemagic

Codemagic must have access to a hosted Git repository containing the complete app, including existing uncommitted baseline/planner/target files. This checkout currently has no configured Git remote. Creating/pushing a repository has not been done as part of this preparation.

1. Put the reviewed project changes in your chosen private Git repository.
2. Connect that repository to your Codemagic personal account.
3. Select codemagic.yaml configuration.
4. Start ios-compile-check manually. No Apple membership/signing credentials are required for this workflow.

The compile workflow pins Flutter 3.47.8 to match the current project SDK requirement and lockfile, uses a Mac M2 runner, enables dependency caching, and runs analysis plus focused authentication/import/reminder tests before compiling. If that exact Flutter version is not available on the selected Codemagic image, select an image supporting it or deliberately update the SDK/lockfile together.

GOOGLE_IOS_CLIENT_ID can be provided as a Codemagic app-level environment variable. If absent, the compile workflow explicitly builds without functioning Google login. Its unsigned .app proves compilation only: it cannot be installed on your iPhone or uploaded to TestFlight. It does not validate callback behavior, Apple signing or runtime permissions.

All builds require network access to restore Dart and Swift packages. Windows-generated Flutter/ephemeral files are ignored and will be regenerated for macOS by Flutter.

Documentation: https://docs.codemagic.io/yaml-quick-start/first-signed-build/

## 3. Apple account and signed TestFlight workflow

After Apple Developer enrollment:

1. Register an App ID for com.premkumar.pocketledger under your Apple developer team.
2. Create the Pocket Ledger iOS app record in App Store Connect with that bundle ID. Copy the numeric Apple ID of the app (not your Apple Account email or team ID).
3. Set up an App Store Connect API key in Codemagic's Apple Developer Portal integration with the access needed for signing and uploading. Name the integration pocket-ledger-app-store, matching codemagic.yaml. Store the private .p8 key in Codemagic; do not paste it into chat, commit it, or put it in a generated xcconfig.
4. Generate/import the App Store distribution signing certificate and provisioning profile for this bundle ID through Codemagic's code signing settings. The ios_signing section selects the matching files; xcode-project use-profiles applies them to Xcode before building. An API integration alone does not supply a missing distribution certificate/private key.
5. Create and make available the environment group pocket_ledger_ios containing:

| Variable | Value |
|---|---|
| GOOGLE_IOS_CLIENT_ID | The real Google OAuth iOS client ID |
| APP_STORE_APPLE_ID | Numeric app ID from App Store Connect |

6. Manually start ios-testflight. It requires both variables, generates native Google configuration, runs checks, applies signing profiles, selects a build number above the current TestFlight build, and exports an IPA.
7. The publishing step uploads the IPA to App Store Connect. Both submit_to_testflight and submit_to_app_store are false: assign internal testers yourself after inspecting the processed build. External testing needs beta review, which you can request in App Store Connect. Public App Store review/release is always a separate manual step.
8. Install the TestFlight app on your iPhone, accept the tester invitation and install Pocket Ledger.

The signed workflow uses the latest available Xcode image because the Windows checkout cannot establish a working Xcode image yet. Record and pin the successful Xcode image after the first native build for reproducibility. Flutter restores Swift packages; explicit CocoaPods installation is unnecessary with the current plugin set.

Build numbering uses the latest TestFlight number plus one, with a floor from the Codemagic project build counter plus 18 (the current Android/source build number). Android versioning is unchanged. Run one release build at a time and wait for Apple processing before another upload to avoid version-number races.

Documentation:
- https://docs.codemagic.io/yaml-code-signing/signing-ios/
- https://docs.codemagic.io/yaml-publishing/app-store-connect/
- https://developer.apple.com/testflight/

## 4. Small first-device test checklist

Before spending cloud minutes on larger feature changes, confirm this vertical slice:

- Cold launch, Google login, cancel login, logout, relaunch and restored login.
- Google consent, refusal, retry and reconnect; read the existing Expense Tracker DB under the same Google account.
- Record one identifiable test expense; verify it in Sheets and on Android/web. Remove the test record afterward.
- Airplane-mode entry and local persistence; reconnect and verify exactly one synchronized record.
- Pick a CSV and XLSX from On My iPhone and iCloud Drive; review, cancel, import and re-import for deduplication. Document-provider downloads must finish before commit.
- Enable a reminder, grant/deny permission, and confirm a scheduled notification when the phone is locked and while the app is open.
- Keyboard, safe areas, scrolling, small-screen layout and dark mode.
- Financial Baseline and Spending Targets: classification, target activation, local progress and persistence.

Mocked tests on Windows establish Dart behavior but do not replace these checks. The first unsigned cloud build establishes native compilation, not complete iOS compatibility.

## 5. App Store submission work still required

Provide your support URL, privacy policy, app description, screenshots, age rating, export-compliance answers and accurate App Privacy disclosures. Audit the archive's privacy report and native SDK privacy manifests; no blanket no-data-collected declaration has been inserted. There are no new broad storage/photo permissions: statement selection uses the existing user-selected document picker.

Document clearly that Google login connects the user's own Sheets/Drive content. Evaluate Apple's login-services exception rather than adding an unrelated Apple account flow prematurely. Assess deletion/disconnection requirements against the actual account/data model, and supply a reviewer-access path (test account or suitable demo mode) that does not expose personal financial data. These review decisions have not been claimed complete.

## 6. Keeping build costs down

Develop and run tests on Windows, then batch iOS changes. Trigger compile or TestFlight builds only when needed. There are no push/PR/schedule triggers in this YAML, no automatic public submission and no automatic tester notifications. Cloud execution has not been started by this task.

Analysis deliberately fails on errors while allowing the repository's existing warnings/info findings. The workflows run the focused iOS-readiness tests without ignore_failure. The complete regression suite still has known unrelated failures; see the implementation handoff for their details. Resolve those before a production release rather than interpreting a successful compile workflow as a complete regression pass.

To regenerate only iOS icons later:

```powershell
dart run tool/generate_ios_icons.dart
```
