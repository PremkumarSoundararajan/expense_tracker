import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_ledger/services/google_sign_in_configuration.dart';

void main() {
  test('native iOS uses its plist client and does not send the web client', () {
    final config = createGoogleSignIn(
      isWeb: false,
      platform: TargetPlatform.iOS,
    );
    expect(config.clientId, isNull);
    expect(config.serverClientId, isNull);
    expect(
      config.scopes,
      contains('https://www.googleapis.com/auth/drive.file'),
    );
    expect(
      config.scopes,
      contains('https://www.googleapis.com/auth/spreadsheets'),
    );
  });
  test('web on an Apple device keeps the web OAuth client', () {
    final config = createGoogleSignIn(
      isWeb: true,
      platform: TargetPlatform.iOS,
    );
    expect(config.clientId, endsWith('.apps.googleusercontent.com'));
    expect(config.serverClientId, isNull);
  });
  test('Android keeps its existing server client and requested scopes', () {
    final config = createGoogleSignIn(
      isWeb: false,
      platform: TargetPlatform.android,
    );
    expect(config.clientId, isNotNull);
    expect(config.serverClientId, config.clientId);
    expect(config.scopes, hasLength(2));
  });
}
