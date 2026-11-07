import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/configure_ios.dart';

void main() {
  const client = '123456789-iosclient.apps.googleusercontent.com';
  test('derives the native callback from the exact configured client ID', () {
    final settings = iosGoogleSignInSettings(' $client ');
    expect(settings, contains('GOOGLE_IOS_CLIENT_ID = $client'));
    expect(
      settings,
      contains(
        'GOOGLE_IOS_REVERSED_CLIENT_ID = com.googleusercontent.apps.123456789-iosclient',
      ),
    );
  });
  test(
    'rejects missing values, the existing web client and injected settings',
    () {
      for (final input in [
        '',
        'replace-me',
        '123-secret',
        '$client\nOTHER = injected',
        '832232205995-r4b63brhvj3kbo193gckj4jgpg5oo2pi.apps.googleusercontent.com',
      ]) {
        expect(() => iosGoogleSignInSettings(input), throwsFormatException);
      }
    },
  );
  test(
    'writes idempotently and leaves existing configuration intact on error',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'pocket-ledger-ios-test-',
      );
      addTearDown(() => temp.delete(recursive: true));
      await Directory('${temp.path}/ios/Flutter').create(recursive: true);
      final file = File('${temp.path}/ios/Flutter/GoogleSignIn.xcconfig');
      await writeIosGoogleSignInSettings(client, temp);
      final first = await file.readAsString();
      await writeIosGoogleSignInSettings(client, temp);
      expect(await file.readAsString(), first);
      await expectLater(
        writeIosGoogleSignInSettings('invalid', temp),
        throwsFormatException,
      );
      expect(await file.readAsString(), first);
    },
  );
}
