import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis/sheets/v4.dart' as sheets;

/// iOS reads its native OAuth client from GIDClientID in Info.plist. A web
/// client cannot replace that client or its matching callback URL scheme.
GoogleSignIn createGoogleSignIn({bool? isWeb, TargetPlatform? platform}) {
  const webClientId =
      '832232205995-r4b63brhvj3kbo193gckj4jgpg5oo2pi.apps.googleusercontent.com';
  final web = isWeb ?? kIsWeb;
  final nativeIos =
      !web && (platform ?? defaultTargetPlatform) == TargetPlatform.iOS;
  return GoogleSignIn(
    clientId: nativeIos ? null : webClientId,
    serverClientId: web || nativeIos ? null : webClientId,
    scopes: [drive.DriveApi.driveFileScope, sheets.SheetsApi.spreadsheetsScope],
  );
}
