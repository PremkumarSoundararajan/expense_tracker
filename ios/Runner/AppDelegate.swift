import Flutter
import GoogleSignIn
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var emailSignInInProgress = false

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "PocketLedgerGoogleAccount") else {
      return
    }
    let channel = FlutterMethodChannel(
      name: "pocket_ledger/google_account", binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "signInWithEmail" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let arguments = call.arguments as? [String: Any],
            let email = arguments["email"] as? String,
            !email.isEmpty,
            let clientID = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String,
            !clientID.isEmpty else {
        result(FlutterError(code: "configuration", message: "Google sign-in is not configured.", details: nil))
        return
      }
      guard let scene = UIApplication.shared.connectedScenes
        .compactMap({ $0 as? UIWindowScene })
        .first(where: { $0.activationState == .foregroundActive }),
            var presenter = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController else {
        result(FlutterError(code: "presentation", message: "Please reopen sign-in and try again.", details: nil))
        return
      }
      while let presented = presenter.presentedViewController {
        presenter = presented
      }
      guard let self = self, !self.emailSignInInProgress else {
        result(FlutterError(code: "in_progress", message: "Sign-in is already in progress.", details: nil))
        return
      }
      self.emailSignInInProgress = true
      GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
      // login_hint uses Google's supported account hint; it never handles passwords.
      GIDSignIn.sharedInstance.signIn(
        withPresenting: presenter,
        hint: email,
        additionalScopes: [
          "https://www.googleapis.com/auth/drive.file",
          "https://www.googleapis.com/auth/spreadsheets"
        ]
      ) { signInResult, error in
        self.emailSignInInProgress = false
        if let error = error as NSError? {
          // GoogleSignIn 8.x declares kGIDSignInErrorCodeCanceled as -5.
          // Match NSError domain/code without relying on Swift enum import naming.
          let googleSignInCanceledCode = -5
          if error.domain == kGIDSignInErrorDomain && error.code == googleSignInCanceledCode {
            result(false)
          } else {
            result(FlutterError(code: "google_sign_in", message: error.localizedDescription, details: nil))
          }
        } else {
          result(signInResult != nil)
        }
      }
    }
  }
}
